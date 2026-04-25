# Guía de Fixes - Consistencia Eventual

## Fixes Rápidos (Orden de Prioridad)

### 1️⃣ FIX INMEDIATO: Double-Booking en Reservaciones

**Archivo a cambiar:** `backend/lib/repositories/reservation_repository.dart`

**Cambio 1: hasConflict() - Agregar FOR UPDATE**
```dart
// ❌ ANTES (Vulnerable)
Future<bool> hasConflict({
  required String deviceId,
  required String date,
  required String startTime,
  required String endTime,
}) async {
  final conn = await getConnection();
  final result = await conn.execute(
    r'''
      SELECT id FROM reservations
      WHERE device_id = $1 AND date = $2 AND status IN ('pending', 'confirmed')
        AND (
          (start_time <= $3 AND end_time > $3) OR
          (start_time < $4 AND end_time >= $4) OR
          (start_time >= $3 AND end_time <= $4)
        )
    ''',
    parameters: [deviceId, date, startTime, endTime],
  );
  return result.isNotEmpty;
}

// ✅ DESPUÉS (Seguro)
Future<bool> hasConflict({
  required String deviceId,
  required String date,
  required String startTime,
  required String endTime,
}) async {
  final conn = await getConnection();
  final result = await conn.execute(
    r'''
      SELECT id FROM reservations
      WHERE device_id = $1 AND date = $2 AND status IN ('pending', 'confirmed')
        AND (
          (start_time <= $3 AND end_time > $3) OR
          (start_time < $4 AND end_time >= $4) OR
          (start_time >= $3 AND end_time <= $4)
        )
      FOR UPDATE
    ''',
    parameters: [deviceId, date, startTime, endTime],
  );
  return result.isNotEmpty;
}
```

⚠️ **Pero cuidado:** `hasConflict()` se llama FUERA de transacción, así que el lock se libera inmediatamente. **SOLUCIÓN: Mover validaciones DENTRO de la transacción de creación.**

---

**Cambio 2: Refactorizar createForStudent() con Transacción**

```dart
// ❌ ANTES (Vulnerable - check-then-act)
Future<Reservation> createForStudent({
  required String studentId,
  required String deviceId,
  required String date,
  required String startTime,
  required String endTime,
}) async {
  final conn = await getConnection();
  final id = Ulid().toString();

  await conn.execute(
    r'''
      INSERT INTO reservations
        (id, booker_type, student_id, device_id, date, start_time, end_time, status)
      VALUES ($1, 'student', $2, $3, $4, $5, $6, 'pending')
    ''',
    parameters: [id, studentId, deviceId, date, startTime, endTime],
  );

  return (await findById(id))!;
}

// ✅ DESPUÉS (Seguro - todo en transacción)
Future<Reservation> createForStudent({
  required String studentId,
  required String deviceId,
  required String date,
  required String startTime,
  required String endTime,
}) async {
  final conn = await getConnection();
  final id = Ulid().toString();

  await conn.runTx((tx) async {
    // 1. Verificar conflictos CON LOCK PESSIMISTIC
    final conflict = await tx.execute(
      r'''
        SELECT id FROM reservations
        WHERE device_id = $1 
          AND date = $2 
          AND status IN ('pending', 'confirmed')
          AND (
            (start_time <= $3 AND end_time > $3) OR
            (start_time < $4 AND end_time >= $4) OR
            (start_time >= $3 AND end_time <= $4)
          )
        FOR UPDATE
      ''',
      parameters: [deviceId, date, startTime, endTime],
    );
    
    if (conflict.isNotEmpty) {
      throw Exception('Device conflict: already booked for this time');
    }

    // 2. Verificar que alumno no tenga otra reserva ese día
    final dailyRes = await tx.execute(
      r'''
        SELECT id FROM reservations
        WHERE student_id = $1 
          AND date = $2 
          AND status IN ('pending', 'confirmed')
        FOR UPDATE
      ''',
      parameters: [studentId, date],
    );
    
    if (dailyRes.isNotEmpty) {
      throw Exception('Student already has reservation on this date');
    }

    // 3. Crear reservación (dentro de TX bloqueada)
    await tx.execute(
      r'''
        INSERT INTO reservations
          (id, booker_type, student_id, device_id, date, start_time, end_time, status)
        VALUES ($1, 'student', $2, $3, $4, $5, $6, 'pending')
      ''',
      parameters: [id, studentId, deviceId, date, startTime, endTime],
    );
  });

  return (await findById(id))!;
}
```

**Cambio 3: Actualizar el endpoint para NO hacer validaciones previas**

**Archivo:** `backend/routes/reservations/index.dart` (_createForStudent)

```dart
// ❌ ANTES (Validaciones fuera de TX)
Future<Response> _createForStudent(
  RequestContext context,
  AuthUser user,
) async {
  // ... validaciones de formato ...
  
  try {
    final device = await DeviceRepository().findById(deviceId);
    if (device == null || device.status != 'available') {
      return error;
    }

    // ... más validaciones ...

    final repo = ReservationRepository();

    if (await repo.studentHasReservationOnDate(
      studentId: user.userId,
      date: date,
    )) {
      return error;
    }

    if (await repo.hasConflict(
      deviceId: deviceId,
      date: date,
      startTime: startTime,
      endTime: endTime,
    )) {
      return error;
    }

    final reservation = await repo.createForStudent(...);
    // ⚠️ Problema: todas las validaciones están fuera
  }
}

// ✅ DESPUÉS (Validaciones dentro de TX)
Future<Response> _createForStudent(
  RequestContext context,
  AuthUser user,
) async {
  // ... validaciones de formato solamente ...
  
  try {
    final student = await StudentRepository().findById(user.userId);
    if (student == null) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Alumno no encontrado'},
      );
    }

    // Validar watchlist (esto es OK hacerlo antes, es solo lectura)
    if (await WatchlistRepository().isBlocked(student.dni)) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Tu cuenta está bloqueada por roturas'},
      );
    }

    // ⚠️ deviceId y date validados de formato, pero NO de business logic
    // Esto se valida DENTRO de createForStudent() en transacción
    
    final repo = ReservationRepository();
    final reservation = await repo.createForStudent(
      studentId: user.userId,
      deviceId: deviceId,
      date: date,
      startTime: startTime,
      endTime: endTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: reservation.toJson(),
    );
  } catch (e) {
    // Capturar excepciones de la transacción
    if (e.toString().contains('conflict') || 
        e.toString().contains('already has')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': e.toString()},
      );
    }
    
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
```

---

### 2️⃣ FIX INMEDIATO: Watchlist incrementDamage() - Race Condition

**Archivo:** `backend/lib/repositories/watchlist_repository.dart`

**Problema:** INSERT duplicado cuando dos threads ejecutan simultáneamente

```dart
// ❌ ANTES (Race condition)
Future<Watchlist> incrementDamage({
  required String dni,
  required String fullName,
}) async {
  final conn = await getConnection();
  final existing = await findByDni(dni); // READ - Línea 58
  
  if (existing == null) {
    // ⚠️ GAP: Otro thread puede insertar aquí
    final id = Ulid().toString();
    await conn.execute(
      r'''
        INSERT INTO watchlist (id, dni, full_name, damage_count, active)
        VALUES ($1, $2, $3, 1, true)
      ''',
      parameters: [id, dni, fullName],
    );
  } else {
    await conn.execute(
      r'''
        UPDATE watchlist
        SET damage_count = damage_count + 1,
            active       = true,
            updated_at   = NOW()
        WHERE dni = $1
      ''',
      parameters: [dni],
    );
  }
  
  return (await findByDni(dni))!;
}

// ✅ DESPUÉS (Seguro - Upsert)
Future<Watchlist> incrementDamage({
  required String dni,
  required String fullName,
}) async {
  final conn = await getConnection();
  
  // SQL 'ON CONFLICT' hace el trabajo de forma atómica
  await conn.execute(
    r'''
      INSERT INTO watchlist (id, dni, full_name, damage_count, active, updated_at)
      VALUES ($1, $2, $3, 1, true, NOW())
      ON CONFLICT(dni) DO UPDATE SET
        damage_count = watchlist.damage_count + 1,
        active       = true,
        updated_at   = NOW()
    ''',
    parameters: [Ulid().toString(), dni, fullName],
  );
  
  return (await findByDni(dni))!;
}
```

Alternativa más clara usando transacción explícita:

```dart
// ✅ ALTERNATIVA: Transacción explícita con FOR UPDATE
Future<Watchlist> incrementDamage({
  required String dni,
  required String fullName,
}) async {
  final conn = await getConnection();
  
  await conn.runTx((tx) async {
    // 1. Lock a la fila si existe
    final existing = await tx.execute(
      r'SELECT id FROM watchlist WHERE dni = $1 FOR UPDATE',
      parameters: [dni],
    );
    
    if (existing.isEmpty) {
      // No existe, insertar
      await tx.execute(
        r'''
          INSERT INTO watchlist (id, dni, full_name, damage_count, active)
          VALUES ($1, $2, $3, 1, true)
        ''',
        parameters: [Ulid().toString(), dni, fullName],
      );
    } else {
      // Existe, actualizar
      await tx.execute(
        r'''
          UPDATE watchlist
          SET damage_count = damage_count + 1,
              updated_at   = NOW()
          WHERE dni = $1
        ''',
        parameters: [dni],
      );
    }
  });
  
  return (await findByDni(dni))!;
}
```

---

### 3️⃣ FIX INMEDIATO: Lectura post-transacción en Retorno

**Archivo:** `backend/routes/returns/index.dart`

**Problema:** Lectura de watchlist FUERA de transacción es inconsistente

```dart
// ❌ ANTES (Inconsistente)
await conn.runTx((tx) async {
  // Todas operaciones
  await tx.execute([INSERT return...]);
  await tx.execute([UPDATE device...]);
  await tx.execute([INSERT damage...]);
  await tx.execute([INSERT/UPDATE watchlist...]);
}); // END TX

// ⚠️ FUERA DE TRANSACCIÓN - Puede cambiar!
String? watchlistStatus;
if (hasDamage && studentDni != null) {
  final entry = await WatchlistRepository().findByDni(studentDni);
  if (entry != null) {
    watchlistStatus = entry.damageCount >= 3
        ? 'bloqueado (${entry.damageCount} roturas)'
        : 'advertencia (${entry.damageCount}/3 roturas)';
  }
}

// ✅ DESPUÉS (Consistente - Leer dentro de TX)
String? watchlistStatus;
await conn.runTx((tx) async {
  // Todas operaciones
  await tx.execute([INSERT return...]);
  await tx.execute([UPDATE device...]);
  
  if (hasDamage && studentDni != null && studentFullName != null) {
    // Registrar daño
    final damageId = Ulid().toString();
    await tx.execute(
      r'''
        INSERT INTO damages (id, dni, return_id, description)
        VALUES ($1, $2, $3, $4)
      ''',
      parameters: [damageId, studentDni, returnId, description],
    );

    // Incrementar watchlist (insert o update)
    final existing = await tx.execute(
      r'SELECT damage_count FROM watchlist WHERE dni = $1 FOR UPDATE',
      parameters: [studentDni],
    );

    if (existing.isEmpty) {
      await tx.execute(
        r'''
          INSERT INTO watchlist (id, dni, full_name, damage_count, active)
          VALUES ($1, $2, $3, 1, true)
        ''',
        parameters: [Ulid().toString(), studentDni, studentFullName],
      );
      watchlistStatus = 'advertencia (1/3 roturas)';
    } else {
      // Obtener el nuevo damage_count DESPUÉS de update
      final updatedCount = (existing.first[0] as int) + 1;
      
      await tx.execute(
        r'''
          UPDATE watchlist
          SET damage_count = $1,
              updated_at   = NOW()
          WHERE dni = $2
        ''',
        parameters: [updatedCount, studentDni],
      );
      
      watchlistStatus = updatedCount >= 3
          ? 'bloqueado ($updatedCount roturas)'
          : 'advertencia ($updatedCount/3 roturas)';
    }
  }
});

final returnModel = await returnRepo.findByCheckout(checkoutId);

return Response.json(
  statusCode: HttpStatus.created,
  body: {
    'return':           returnModel!.toJson(),
    'watchlist_status': watchlistStatus,
  },
);
```

---

### 4️⃣ FIX IMPORTANTE: Device Status Validation en Checkout

**Archivo:** `backend/routes/checkouts/index.dart`

**Problema:** Validación de device status fuera de transacción

```dart
// ❌ ANTES (Status puede cambiar entre validación y checkout)
final device = await DeviceRepository().findById(reservation.deviceId);
if (device == null || device.status != 'available') {
  return error; // ← device.status fue 'available'
}

// ⚠️ GAP: Otro endpoint podría hacer return aquí, cambiando status

final checkout = await CheckoutRepository().approveCheckout(...);

// ✅ DESPUÉS (Validar dentro de transacción)
// Mover validación DENTRO del approveCheckout()
final checkout = await CheckoutRepository().approveCheckout(
  reservationId: reservationId,
  adminId: user.userId,
  deviceId: reservation.deviceId,
  deviceNotes: deviceNotes,
  studentId: student?.id,
  activateStudent: wasInactive,
);

// Y actualizar approveCheckout():
Future<Checkout> approveCheckout({
  required String reservationId,
  required String adminId,
  required String deviceId,
  required String? deviceNotes,
  required String? studentId,
  required bool activateStudent,
}) async {
  final conn = await getConnection();
  final id = Ulid().toString();

  await conn.runTx((tx) async {
    // 1. Validar device status DENTRO de TX
    final device = await tx.execute(
      r'SELECT status FROM devices WHERE id = $1 FOR UPDATE',
      parameters: [deviceId],
    );
    
    if (device.isEmpty || device.first[0] as String != 'available') {
      throw Exception('Device is not available');
    }

    // 2. Validar reservation status DENTRO de TX
    final reservation = await tx.execute(
      r'SELECT status FROM reservations WHERE id = $1 FOR UPDATE',
      parameters: [reservationId],
    );
    
    if (reservation.isEmpty || 
        !(reservation.first[0] as String).contains('pending|confirmed')) {
      throw Exception('Reservation is not in valid state');
    }

    // 3. Crear checkout
    await tx.execute(
      r'''
        INSERT INTO checkouts (id, reservation_id, admin_id, device_notes)
        VALUES ($1, $2, $3, $4)
      ''',
      parameters: [id, reservationId, adminId, deviceNotes],
    );

    // 4. Device: available → in_use
    await tx.execute(
      r'UPDATE devices SET status = $1 WHERE id = $2',
      parameters: ['in_use', deviceId],
    );

    // 5. Reserva: pending/confirmed → completed
    await tx.execute(
      r'UPDATE reservations SET status = $1 WHERE id = $2',
      parameters: ['completed', reservationId],
    );

    // 6. Activar alumno si corresponde (primer retiro)
    if (activateStudent && studentId != null) {
      await tx.execute(
        r'UPDATE students SET is_active = true WHERE id = $1',
        parameters: [studentId],
      );
    }
  });

  return (await findByReservation(reservationId))!;
}
```

---

### 5️⃣ FIX IMPORTANTE: Serialización de Expiración

**Archivo:** `backend/lib/repositories/tasks/expire_reservations_task.dart`

**Problema:** Puede ejecutarse 2+ veces simultáneamente en instancias paralelas

```dart
// ❌ ANTES (Sin lock)
void startExpireReservationsTask() {
  Logger.root.level = Level.INFO;

  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final expired = await ReservationRepository().expireOverdue();
      if (expired > 0) {
        _logger.info('Se expiraron $expired reservas');
      }
    } catch (e) {
      _logger.severe('Error al expirar reservas: $e');
    }
  });
}

// ✅ DESPUÉS (Con DB advisory lock)
void startExpireReservationsTask() {
  Logger.root.level = Level.INFO;

  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final expired = await ReservationRepository().expireOverdueWithLock();
      if (expired > 0) {
        _logger.info('Se expiraron $expired reservas');
      }
    } catch (e) {
      _logger.severe('Error al expirar reservas: $e');
    }
  });
}

// Nueva metodología en reservation_repository.dart
Future<int> expireOverdueWithLock() async {
  final conn = await getConnection();
  
  // PostgreSQL advisory lock (id 12345 arbitrary)
  await conn.execute('SELECT pg_advisory_lock(12345)');
  
  try {
    return await expireOverdue();
  } finally {
    // SIEMPRE liberar el lock
    await conn.execute('SELECT pg_advisory_unlock(12345)');
  }
}
```

---

## Tabla de Cambios Requeridos

| Archivo | Función | Cambio | Prioridad |
|---------|---------|--------|-----------|
| reservation_repository.dart | createForStudent | Agregar validaciones en TX | 🔴 CRÍTICA |
| reservation_repository.dart | createForTeacher | Agregar validaciones en TX | 🔴 CRÍTICA |
| reservation_repository.dart | hasConflict | Agregar FOR UPDATE | 🟡 MEDIA |
| watchlist_repository.dart | incrementDamage | Usar ON CONFLICT upsert | 🔴 CRÍTICA |
| checkout_repository.dart | approveCheckout | Validar device dentro TX | 🔴 CRÍTICA |
| routes/checkouts/index.dart | onRequest | Remover validaciones previas | 🔴 CRÍTICA |
| routes/returns/index.dart | onRequest | Leer watchlist dentro TX | 🟠 ALTA |
| reservation_repository.dart | expireOverdue | Agregar advisory lock | 🟡 MEDIA |

---

## Testing Checklist

- [ ] Test: Simultaneous bookings (esperado: solo 1 succeeds)
- [ ] Test: Parallel damage increments (esperado: count correcto)
- [ ] Test: Concurrent checkouts (esperado: 1 succeeds)
- [ ] Test: Watchlist status leer post-transaction (esperado: consistent)
- [ ] Test: Device status durante checkout/return (esperado: nunca inconsistent)
- [ ] Test: Expire task idempotente (esperado: mismo resultado 2 ejecuciones)
- [ ] Load test: 100 requests/sec a crear reservaciones
- [ ] Chaos test: Kill conexión mid-transaction (esperado: rollback)
