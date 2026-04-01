---
name: logging-patterns
description: Java logging best practices with SLF4J, structured logging (JSON), and MDC for request tracing. Use when user asks about logging, debugging application flow, or analyzing logs.
---

# Logging Patterns for Spring Boot 4

Effective logging for Spring Boot 4.x / Java 25 applications with structured, AI-parsable formats.

- [Structured Logging Setup](#structured-logging-setup)
- [SLF4J Basics](#slf4j-basics)
- [MDC for Request Tracing](#mdc-for-request-tracing)
- [Logging Levels Guide](#logging-levels-guide)
- [AI-Friendly Log Analysis](#ai-friendly-log-analysis)

## Structured Logging Setup

Spring Boot 4 has built-in structured logging support — no extra dependencies needed.

### application.yml

```yaml
logging:
  structured:
    format:
      console: logstash    # or "ecs" for Elastic Common Schema, "gelf" for Graylog

  level:
    root: INFO
    com.companyname.appname: DEBUG
    org.springframework.web: WARN
    org.hibernate.SQL: DEBUG
    org.hibernate.orm.jdbc.bind: TRACE   # show bind parameter values
```

### Profile-Based Switching

```yaml
# application.yml (default - JSON for production/AI)
spring:
  profiles:
    default: json-logs

---
spring:
  config:
    activate:
      on-profile: json-logs
logging:
  structured:
    format:
      console: logstash

---
spring:
  config:
    activate:
      on-profile: human-logs
logging:
  pattern:
    console: "%d{HH:mm:ss.SSS} %-5level [%thread] %logger{36} - %msg%n"
```

**Usage:**
```bash
# Default: JSON (for AI, CI/CD, production)
./mvnw spring-boot:run

# Human-readable when needed
./mvnw spring-boot:run -Dspring.profiles.active=human-logs
```

## SLF4J Basics

### Logger Declaration

No Lombok — always declare the logger manually.

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);
}
```

### Parameterized Logging

```java
// GOOD: Evaluated only if level enabled
log.debug("Processing order {} for user {}", orderId, userId);

// BAD: Always concatenates (avoid)
log.debug("Processing order " + orderId + " for user " + userId);

// For expensive operations, guard the call
if (log.isDebugEnabled()) {
    log.debug("Order details: {}", order.toDetailedString());
}
```

### Log Levels

```java
log.error("Payment failed for order {}", orderId, exception);   // system broken
log.warn("Retry attempt {} for order {}", attempt, orderId);     // something wrong but recoverable
log.info("Order {} created for user {}", orderId, userId);       // business events
log.debug("Validating order items: {}", items.size());           // development diagnostics
log.trace("Item validation result: {}", validationResult);       // detailed trace
```

### Exception Logging

```java
// GOOD: Exception as last argument — SLF4J prints full stack trace
log.error("Failed to process order {}", orderId, exception);

// BAD: Exception in placeholder — only prints toString()
log.error("Failed to process order {} with error {}", orderId, exception);
```

## MDC for Request Tracing

### MDC Filter for HTTP Requests

```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestTracingFilter extends OncePerRequestFilter {

    private static final String REQUEST_ID = "requestId";
    private static final String USER_ID = "userId";

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        try {
            String requestId = request.getHeader("X-Request-ID");
            if (requestId == null || requestId.isBlank()) {
                requestId = UUID.randomUUID().toString().substring(0, 8);
            }
            MDC.put(REQUEST_ID, requestId);

            String userId = request.getHeader("X-User-ID");
            if (userId != null) {
                MDC.put(USER_ID, userId);
            }

            response.setHeader("X-Request-ID", requestId);
            filterChain.doFilter(request, response);
        } finally {
            MDC.clear();
        }
    }
}
```

### Using MDC Values in Logs

MDC values are automatically included in structured JSON output. In log messages:

```java
// MDC fields (requestId, userId) are automatically attached to every log line
log.info("Order {} created, total: {}", orderId, total);

// Output (with logstash format):
// {"timestamp":"...","level":"INFO","message":"Order 123 created, total: 99.99",
//  "requestId":"a1b2c3d4","userId":"user-789","logger":"...OrderService"}
```

### MDC in Async / Virtual Threads

For Spring Boot 4 with virtual threads, propagate MDC context:

```java
import org.slf4j.MDC;
import org.springframework.core.task.TaskDecorator;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        return () -> {
            try {
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                runnable.run();
            } finally {
                MDC.clear();
            }
        };
    }
}
```

Register it in configuration:

```java
@Configuration
public class AsyncConfig {

    @Bean
    public TaskExecutor taskExecutor(MdcTaskDecorator mdcTaskDecorator) {
        var executor = new ThreadPoolTaskExecutor();
        executor.setTaskDecorator(mdcTaskDecorator);
        executor.setCorePoolSize(5);
        executor.setMaxPoolSize(10);
        executor.initialize();
        return executor;
    }
}
```

## Logging Levels Guide

### What to Log at Each Level

| Level | Use for | Example |
|-------|---------|---------|
| `ERROR` | System failures requiring attention | Database connection lost, payment gateway down |
| `WARN` | Unexpected but recoverable situations | Retry succeeded, fallback triggered, deprecated API called |
| `INFO` | Business events and milestones | Order created, user registered, job completed |
| `DEBUG` | Development diagnostics | Method entry/exit, intermediate calculations |
| `TRACE` | Detailed internal state | Full request/response bodies, SQL bind values |

### What NOT to Log

- Passwords, tokens, secrets, credit card numbers
- Full request/response bodies at INFO level (use DEBUG/TRACE)
- Repetitive logs inside tight loops without rate limiting
- Stack traces for expected business exceptions (use WARN without trace)

### Spring Boot 4 Logging Configuration

```yaml
logging:
  level:
    root: INFO
    com.companyname.appname: DEBUG
    # Spring Framework
    org.springframework.web: WARN
    org.springframework.security: WARN
    org.springframework.transaction: DEBUG     # transaction boundaries
    # Hibernate / JPA
    org.hibernate.SQL: DEBUG                   # show SQL statements
    org.hibernate.orm.jdbc.bind: TRACE         # show bind parameters
    # Connection pool
    com.zaxxer.hikari: WARN
```

## AI-Friendly Log Analysis

### Why JSON Logs for AI/Claude Code

```
# Text format — AI must "interpret" the string
2026-01-29 10:15:30 INFO OrderService - Order 12345 created for user-789, total: 99.99

# JSON format — AI extracts fields directly
{"timestamp":"2026-01-29T10:15:30Z","level":"INFO","orderId":12345,"userId":"user-789","total":99.99}
```

### Analyzing Logs

```bash
# Get recent errors
cat app.log | jq 'select(.level == "ERROR")' | tail -20

# Follow specific request
cat app.log | jq 'select(.requestId == "a1b2c3d4")'

# Find slow operations
cat app.log | jq 'select(.duration_ms > 1000)'

# Group errors by logger
cat app.log | jq 'select(.level == "ERROR") | .logger_name' | sort | uniq -c | sort -rn
```

### Service Layer Logging Pattern

```java
@Service
@Transactional(readOnly = true)
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository orderRepository;

    public OrderService(OrderRepository orderRepository) {
        this.orderRepository = orderRepository;
    }

    @Transactional
    public OrderResponse create(CreateOrderRequest request) {
        log.info("Creating order for customer {}", request.customerId());

        Order order = new Order();
        order.setCustomerId(request.customerId());
        order.setStatus(OrderStatus.PENDING);
        Order saved = orderRepository.save(order);

        log.info("Order {} created with status {}", saved.getId(), saved.getStatus());
        return toResponse(saved);
    }

    public OrderResponse findById(Long id) {
        log.debug("Finding order by id {}", id);
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> {
                    log.warn("Order not found with id {}", id);
                    return new ResourceNotFoundException("Order not found with id: " + id);
                });
        return toResponse(order);
    }
}
```

### Controller Logging Pattern

Controllers generally don't need logging — the MDC filter handles request tracing and Spring Boot logs request/response at DEBUG level automatically. Add logging only for non-obvious flows:

```java
@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @PostMapping
    public ResponseEntity<OrderResponse> create(@Valid @RequestBody CreateOrderRequest request) {
        // No log needed here — service layer logs the business event
        OrderResponse order = orderService.create(request);
        return ResponseEntity.created(URI.create("/api/orders/" + order.id())).body(order);
    }
}
```