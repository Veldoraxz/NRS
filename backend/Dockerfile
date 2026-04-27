FROM dart:stable AS build

WORKDIR /app

# Copy dependency files first for caching
COPY pubspec.yaml pubspec.lock* ./

# Install dependencies
RUN dart pub get

# Copy the rest of the source
COPY . .

# Install dart_frog_cli and build
RUN dart pub global activate dart_frog_cli
RUN dart_frog build

# Compile the server
RUN dart compile exe build/bin/server.dart -o build/bin/server

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/build/bin/server /app/bin/server

ENV PORT=8080
EXPOSE 8080

CMD ["/app/bin/server"]
