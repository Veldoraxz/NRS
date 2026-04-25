# Análisis de Consistencia Eventual - NRS Backend

## Resumen Ejecutivo

El sistema actual tiene **múltiples puntos críticos de inconsistencia eventual** que pueden causar:
- Overbooking de dispositivos (double-bookings)
- Estados desincronizados entre reservaciones y dispositivos
- Watchlist incoherente (daños registrados pero no contabilizados)
- Activación de estudiantes duplicada o inconsistent
- Race conditions en validaciones de disponibilidad

## Problemas Identificados

### 1. ⚠️ **CRÍTICO: Race Condition en Creación de Reservaciones**

**Ubicación:** `routes/reservations/index.dart` (_createForStudent, _createForTeacher)

**Problema:**
```
VALIDACIÓN                    CREACIÓN
[hasConflict]  ←→  T1  ←→ [createForStudent]
               Race Window
                    ↑
                T2 puede crear aquí
```

Entre `hasConflict()` (línea 122-132) y `createForStudent()` (línea 134-140):
1. Thread T1 valida que no hay conflicto ✓
2. Thread T2 crea una reservación conflictiva simultáneamente
3. Thread T1 crea otra reservación conflictiva
4. **Resultado: Dos reservaciones en el mismo horario**

**Impacto:** `ALTA` - Overbooking directo

**Código Vulnerable:**
```dart
if (await repo.hasConflict(...)) { // Line 122-132
  return Response.json(...);
}
// ⚠️ GAP: Otro request podría crear aquí

final reservation = await repo.createForStudent(...); // Line 134-140
```

---

### 2. ⚠️ **CRÍTICO: Lectura No Transaccional en Watchlist**

**Ubicación:** `repositories/watchlist_repository.dart` - `incrementDamage()`

**Problema:**
```
LECTURA              ESCRITURA
[findByDni] → Check  ↓
            Null?    [INSERT/UPDATE]
            ↑
            Gap: Otro thread crea aquí
```

**Código Vulnerable:**
```dart
Future<Watchlist> incrementDamage({...}) async {
  final existing = await findByDni(dni);  // READ - Línea 58
  
  if (existing == null) {
    // ⚠️ GAP: Si otro thread crea aquí, ambos INSERTan
    await conn.execute([INSERT...]);      // WRITE - Línea 62-67
  }
}
```

**Race Condition:**
1. T1 : `findByDni(dni)` → NULL
2. T2 : `findByDni(dni)` → NULL (paralelo a T1)
3. T1 : INSERT → OK
4. T2 : INSERT → ERROR (UNIQUE constraint) o duplicado logic

**Impacto:** `ALTA` - Violación de integridad, errores 500

---

### 3. ⚠️ **CRÍTICO: Transacción Incompleta en Retorno de Dispositivos**

**Ubicación:** `routes/returns/index.dart`

**Problema:**
```
TRANSACCIÓN              LECTURA POSTERIOR
[tx.execute]  ✓         [WatchlistRepository]
  - INSERT return        - findByDni()
  - UPDATE device        ⚠️ GAP: Inconsistent read
  - INSERT damage
  - INSERT/UPDATE watchlist
              ↓
         FIN TRANSACCIÓN
              ↓
         LECTURA FUERA DE TX
```

**Código Vulnerable:**
```dart
await conn.runTx((tx) async {
  // 1-3: Todas las operaciones dentro de TX ✓
  await tx.execute([INSERT return...]);
  await tx.execute([UPDATE device...]);
  await tx.execute([INSERT damage...]);
  await tx.execute([UPDATE/INSERT watchlist...]);
}); // FIN TRANSACCIÓN

// ⚠️ LECTURA FUERA DE TRANSACCIÓN
final entry = await WatchlistRepository().findByDni(studentDni); // Line 152
watchlistStatus = entry.damageCount >= 3 ? 'bloqueado' : 'advertencia';
```

**Riesgo:**
- Entre la COMMIT de la transacción y la lectura, otro proceso podría modificar watchlist
- El estado reportado en la respuesta podría no coincidir con la BD

**Impacto:** `MEDIA` - Inconsistencia de datos en respuesta, confusión UI

---

### 4. ⚠️ **CRÍTICO: Falta de Atomicidad en Transacciones de Reservaciones**

**Ubicación:** `repositories/checkout_repository.dart` - `approveCheckout()`

**Problema:** Aunque `approveCheckout()` usa transacción, hay validaciones previas fuera de la TX:

```dart
// FUERA DE TRANSACCIÓN (routes/checkouts/index.dart, líneas 29-74)
if (reservation.status != 'pending' && reservation.status != 'confirmed') { }
if (await reservationRepo.hasActiveCheckout(reservationId)) { }
if (device == null || device.status != 'available') { }
                                           ↓
                        ⚠️ GAP: Device status podría cambiar aquí

// DENTRO DE TRANSACCIÓN (líneas 94-101)
await CheckoutRepository().approveCheckout(...)
```

**Race Condition:**
1. Validamos: `device.status == 'available'` ✓
2. T2 hace retorno: device pasa a 'available' → 'in_use'
3. Luego T2 hace otro checkout: device pasa a 'in_use' → 'available'
4. Nuestro checkout intenta: UPDATE device SET status = 'in_use'
5. **Resultado: Múltiples checkouts simultáneamente**

**Impacto:** `ALTA` - Device status corrupted, lógica de inventory fallida

---

### 5. ⚠️ **ALTO: Sin Lock Pessimistic en Validación de Conflictos**

**Ubicación:** `repositories/reservation_repository.dart` - `hasConflict()`

**Problema:** No usa FOR UPDATE para bloquear las filas durante validación:

```dart
Future<bool> hasConflict({...}) async {
  final result = await conn.execute(
    r'''
      SELECT id FROM reservations
      WHERE device_id = $1 AND date = $2 AND status IN ('pending', 'confirmed')
      -- ⚠️ NO HAY: FOR UPDATE
      -- ⚠️ SIN LOCK: Otro request puede insertar entre SELECT y INSERT
    ''',
  );
  return result.isNotEmpty;
}
```

**Solución Esperada:**
```sql
SELECT id FROM reservations WHERE ... FOR UPDATE;
```

**Impacto:** `ALTA` - Double bookings persistentes

---

### 6. ⚠️ **ALTO: Expiración de Reservaciones sin Serialización**

**Ubicación:** `repositories/tasks/expire_reservations_task.dart`

**Problema:**
```
TIMER EJECUTA CADA 1 MIN
        ↓
    [expireOverdue()]
        ↓
    UPDATE reservations SET status = 'expired' ...
        ↑
Pueden ejecutarse 2+ instancias simultáneamente (workers/instancias paralelas)
```

```dart
void startExpireReservationsTask() {
  Timer.periodic(const Duration(minutes: 1), (_) async {
    final expired = await ReservationRepository().expireOverdue();
    // ⚠️ Sin lock: Si se ejecuta en 2 instances paralelas
    // ambas pueden actualizar las mismas filas
  });
}
```

**Riesgo:**
- No hay deduplicación: la misma reservación se expira 2x en una carrera
- No es idempotent en contexto distribuido
- Incrementa logs innecesarios sin dañar datos, pero es ineficiente

**Impacto:** `MEDIA` - Ineficiencia, logs corruptos, sin data corruption

---

### 7. ⚠️ **ALTO: Activación de Estudiantes sin Garantía de Atomicidad**

**Ubicación:** `repositories/checkout_repository.dart` - `approveCheckout()` + `routes/checkouts/index.dart`

**Problema:**
```
VALIDACIÓN (no-transaccional)   ESCRITURA (transaccional)
[student.isActive = false?]  →  [UPDATE students SET is_active = true]
        ↓
    ⚠️ GAP: Otro checkout activa al mismo tiempo
        ↓
    Ambos condicionales pasan, ambos activan
```

**Código Vulnerable:**
```dart
// routes/checkouts/index.dart línea 68-70
final student = await studentRepo.findById(reservation.studentId!);
final wasInactive = student != null && !student.isActive;

// ⚠️ GAP: Entre aquí...
// routes/checkouts/index.dart línea 94-101
await CheckoutRepository().approveCheckout(
  activateStudent: wasInactive, // ← Basado en lectura vieja
);
```

**Race Condition:**
1. T1: Lee student → isActive = false
2. T2: Lee student → isActive = false (paralelo)
3. T1: UPDATE students SET is_active = true
4. T2: UPDATE students SET is_active = true (redundante pero ok)
5. **Resultado: Log confuso, event duplicados, pero sin data corruption**

**Impacto:** `BAJA` - Redundancia, ineficiencia, sin cambios de estado incorrecto

---

### 8. ⚠️ **MEDIO: Inconsistencia en Conteo de Daños**

**Ubicación:** `routes/returns/index.dart` líneas 109-147

**Problema:** Daños se cuentan en watchlist en la misma transacción, pero:
- Si la transacción falla parcialmente (rollback), el registro de daño se pierde pero se pudo haber logeado
- No hay compensación si el INSERT de watchlist falla después del INSERT de damage

**Código:**
```dart
await conn.runTx((tx) async {
  // 1. INSERT return ✓
  // 2. UPDATE device ✓
  
  // 3. INSERT damage ← Si falla aquí no hay compensation
  await tx.execute([INSERT damage...]);
  
  // 4. INSERT/UPDATE watchlist ← Si falla aquí, damage queda huérfano
  await tx.execute([INSERT watchlist...]);
});
```

**Riesgo:** Daños sin contabilizar en watchlist, estudiantes no bloqueados cuando deberían estarlo

**Impacto:** `MEDIA` - Inconsistencia lógica, estudiantes "pueden escaparse"

---

### 9. ⚠️ **BAJO: Lectura No Repetible en Validaciones**

**Ubicación:** `routes/reservations/index.dart` - `_createForStudent()` líneas 83-92

**Problema:** Validación de watchlist fuera de transacción:

```dart
if (await WatchlistRepository().isBlocked(student.dni)) {
  return Response.json(...blocked...);
}
// ⚠️ GAP: Estudiante podría ser bloqueado aquí
await repo.createForStudent(...); // Crea reservación
```

**Riesgo:** Estudiante es bloqueado entre validación y creación, pero crea reservación anyway

**Impacto:** `BAJA` - Violación de regla de negocio, pero no data corruption

---

## Matriz de Riesgos

| Problema | Severidad | Tipo | Frecuencia | Mitigación |
|----------|-----------|------|-----------|-----------|
| Double-booking en reservaciones | 🔴 CRÍTICA | Race Condition | Frecuente | SELECT FOR UPDATE |
| Watchlist incrementDamage | 🔴 CRÍTICA | Race Condition | Frecuente | Transacción + SELECT FOR UPDATE |
| Lectura post-TX en retorno | 🟠 ALTA | Inconsistencia | Ocasional | Leer dentro de TX |
| Validación device status | 🔴 CRÍTICA | Race Condition | Frecuente | SELECT FOR UPDATE en TX |
| Sin lock pessimistic | 🟠 ALTA | Race Condition | Frecuente | FOR UPDATE |
| Expiración no serializada | 🟡 MEDIA | Ineficiencia | Frecuente | Distributed lock (Redis/DB) |
| Activación estudiante | 🟡 BAJA | Redundancia | Ocasional | Lectura en transacción |
| Watchlist huérfano | 🟡 MEDIA | Inconsistencia | Rara | Mejor rollback logic |
| Lectura de watchlist bloqueada | 🟡 BAJA | Violación de regla | Ocasional | Validar en transacción |

---

## Patrones de Fallo Comunes

### 1. Check-Then-Act sin Transacción
```dart
// ❌ INCORRECTO
if (await someCheck()) {
  await someAction(); // ← Can fail between check and action
}

// ✅ CORRECTO
await conn.runTx((tx) async {
  final isOk = await tx.execute('... FOR UPDATE ...');
  if (isOk.isNotEmpty) {
    await tx.execute([INSERT/UPDATE]);
  }
});
```

### 2. Lectura + Decisión + Escritura en 3 pasos
```dart
// ❌ INCORRECTO
final existing = await findByDni(dni);
if (existing == null) {
  await insert(...); // ← Otro thread puede insertar aquí
}

// ✅ CORRECTO
await conn.runTx((tx) async {
  final existing = await tx.execute('SELECT ... FOR UPDATE ...');
  if (existing.isEmpty) {
    await tx.execute([INSERT]);
  }
});
```

### 3. Validación fuera de Transacción
```dart
// ❌ INCORRECTO
if (device.status == 'available') { // ← Status podría cambiar
  await approveCheckout(...);
}

// ✅ CORRECTO
await conn.runTx((tx) async {
  final device = await tx.execute('SELECT ... WHERE id = $1 FOR UPDATE');
  if (device[0].status == 'available') {
    // device está lockeado, status no puede cambiar
    await tx.execute([UPDATE]);
  }
});
```

---

## Recomendaciones de Solución

### Fase 1: Críticos (Implementar YA)

1. **Agregar SELECT FOR UPDATE en todas las validaciones**
   - `hasConflict()`: Agregar `FOR UPDATE` en SELECT
   - `hasActiveCheckout()`: Agregar `FOR UPDATE`
   - Colocar las validaciones DENTRO de la transacción

2. **Refactorizar `incrementDamage()`**
   - Usar `INSERT ... ON CONFLICT DO UPDATE` (upsert)
   - O: SELECT ... FOR UPDATE, luego decidir INSERT vs UPDATE

3. **Trasladar validaciones DENTRO de transacciones**
   - checkouts/index.dart: validar device status en TX
   - reservations/index.dart: validar conflictos en TX

### Fase 2: Altos (Próximo Sprint)

4. **Mover lectura de watchlist dentro de transacción**
   - returns/index.dart: Leer watchlist dentro de TX, o guardar el estado calculado

5. **Implementar serialización de expiración**
   - Usar DB-level advisory lock
   - O: Distributed lock (Redis)
   - O: Event sourcing + processed flag

### Fase 3: Medios (Futuro)

6. **Mejorar compensación de transacciones**
   - Agregar triggers para compensación de daños
   - O: Saga pattern con event log

7. **Validar watchlist bloqueado en TX**
   - Mover `isBlocked()` check dentro de TX de creación

---

## Ejemplo de Refactor: Double-Booking Fix

### Antes (Vulnerable):
```dart
if (await repo.hasConflict(deviceId, date, startTime, endTime)) {
  return error;
}
if (await repo.studentHasReservationOnDate(studentId, date)) {
  return error;
}
final reservation = await repo.createForStudent(...);
```

### Después (Seguro):
```dart
final conn = await getConnection();
final reservation = await conn.runTx((tx) async {
  // 1. Verificar conflictos CON LOCK
  final conflict = await tx.execute(
    r'''
      SELECT id FROM reservations
      WHERE device_id = $1 
        AND date = $2 
        AND status IN ('pending', 'confirmed')
        AND ((start_time <= $3 AND end_time > $3) 
          OR (start_time < $4 AND end_time >= $4)
          OR (start_time >= $3 AND end_time <= $4))
      FOR UPDATE
    ''',
    parameters: [deviceId, date, startTime, endTime],
  );
  
  if (conflict.isNotEmpty) throw Exception('Conflict!');
  
  // 2. Verificar una reserva por día
  final dailyRes = await tx.execute(
    r'SELECT id FROM reservations WHERE student_id = $1 AND date = $2 FOR UPDATE',
    parameters: [studentId, date],
  );
  
  if (dailyRes.isNotEmpty) throw Exception('Already has reservation!');
  
  // 3. Crear reservación (dentro de TX)
  await tx.execute([INSERT reservation...]);
  
  // 4. Retornar
  return await findById(id);
});

return Response.json(statusCode: HttpStatus.created, body: reservation.toJson());
```

---

## Testing

### Casos de Prueba para Race Conditions

```dart
// Test: Simultaneous bookings del mismo dispositivo
test('No permite double-booking con requests paralelos', () async {
  final futures = <Future>[];
  for (int i = 0; i < 2; i++) {
    futures.add(createReservation(deviceId, date, startTime, endTime));
  }
  final results = await Future.wait(futures, eagerError: false);
  expect(results.where((r) => r.isSuccess).length, equals(1)); // Solo uno succeeds
});

// Test: Simultaneous increments en watchlist
test('Watchlist damage count es correcto con parallelismo', () async {
  final futures = <Future>[];
  for (int i = 0; i < 5; i++) {
    futures.add(watchlistRepo.incrementDamage(dni, fullName));
  }
  await Future.wait(futures);
  
  final entry = await watchlistRepo.findByDni(dni);
  expect(entry.damageCount, equals(5)); // No 1, no duplicates
});
```

---

## Referencias

- PostgreSQL Transaction Documentation: https://www.postgresql.org/docs/current/transaction-iso.html
- SELECT FOR UPDATE: https://www.postgresql.org/docs/current/sql-select.html#SQL-FOR-UPDATE-SHARE
- Dart Postgres Package: https://pub.dev/packages/postgres
- Isolation Levels: https://en.wikipedia.org/wiki/Isolation_(database_systems)
