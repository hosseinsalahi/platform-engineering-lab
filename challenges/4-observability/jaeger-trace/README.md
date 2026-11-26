# Configure Application Tracing with Jaeger

**Time:** 7 minutes
**Skills tested:** Distributed Tracing, OpenTelemetry, Jaeger

## Context

The platform team has deployed Jaeger for distributed tracing. You need to configure an application to send traces to the Jaeger collector using OpenTelemetry environment variables.

## Task

Configure tracing for the `order-service` in namespace `cnpe-tracing-test`:

1. Deploy the **Jaeger** collector (provided in setup)
2. Create the **order-service** deployment with correct OTEL configuration
3. Verify traces can be sent to Jaeger

## Requirements

**order-service Deployment:**
- Image: nginx:1.25
- Environment variables:
  - `OTEL_SERVICE_NAME`: order-service
  - `OTEL_EXPORTER_OTLP_ENDPOINT`: http://jaeger-collector:4317
  - `OTEL_PROPAGATORS`: tracecontext,baggage

## Verification

The exercise validates:
1. Deployment has correct OTLP endpoint
2. Deployment has OTEL_PROPAGATORS configured
3. Pod is running successfully

## Allowed Documentation

- [Jaeger Getting Started](https://www.jaegertracing.io/docs/latest/getting-started/)
- [OpenTelemetry Environment Variables](https://opentelemetry.io/docs/concepts/sdk-configuration/)
