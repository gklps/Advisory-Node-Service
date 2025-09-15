# Use the official Go image as base
FROM golang:1.23-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git gcc musl-dev

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=1 GOOS=linux go build -a -installsuffix cgo -o advisory-node main_db.go

# Use minimal base image for runtime
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata

# Set working directory
WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/advisory-node .

# Expose port
EXPOSE 8080

# Set default environment variables
ENV GIN_MODE=release
ENV PORT=8080
ENV DB_TYPE=postgres
ENV DB_SSL_MODE=require

# Run the application
CMD ["./advisory-node", "-port=8080", "-mode=release"]
