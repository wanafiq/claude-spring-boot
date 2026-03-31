# Spring Service Layer

- [Key principles](#key-principles)
- [Basic service](#basic-service)
- [Transaction management](#transaction-management)
- [Domain exceptions](#domain-exceptions)
- [DTO mapping](#dto-mapping)
- [Service composition](#service-composition)

## Key principles

Follow these principles when creating Spring Service layer components:

- Create service classes that perform a Unit of Work
- Use `@Transactional` for all write operations
- Use `@Transactional(readOnly = true)` for all read operations
- Use constructor injection exclusively — no field injection
- Return DTOs from public methods — never expose entities to controllers
- Throw domain-specific exceptions — let `@RestControllerAdvice` handle HTTP mapping
- Keep services focused on business logic — no HTTP concerns (status codes, headers, request/response)
- Favor composition over inheritance — inject other services rather than extending base classes

## Basic service

```java
package com.companyname.appname.service;

import com.companyname.appname.dto.CreateProductRequest;
import com.companyname.appname.dto.ProductResponse;
import com.companyname.appname.dto.UpdateProductRequest;
import com.companyname.appname.exception.ResourceNotFoundException;
import com.companyname.appname.model.Product;
import com.companyname.appname.repository.ProductRepository;
import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class ProductService {

    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public ProductResponse findById(Long id) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found with id: " + id));
        return toResponse(product);
    }

    public Page<ProductResponse> findAll(Pageable pageable) {
        return productRepository.findAll(pageable).map(this::toResponse);
    }

    public List<ProductResponse> search(String name) {
        return productRepository.findByNameContainingIgnoreCase(name).stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional
    public ProductResponse create(CreateProductRequest request) {
        Product product = new Product();
        product.setName(request.name());
        product.setPrice(request.price());
        Product saved = productRepository.save(product);
        return toResponse(saved);
    }

    @Transactional
    public ProductResponse update(Long id, UpdateProductRequest request) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Product not found with id: " + id));
        product.setName(request.name());
        product.setPrice(request.price());
        Product saved = productRepository.save(product);
        return toResponse(saved);
    }

    @Transactional
    public void delete(Long id) {
        if (!productRepository.existsById(id)) {
            throw new ResourceNotFoundException("Product not found with id: " + id);
        }
        productRepository.deleteById(id);
    }

    private ProductResponse toResponse(Product product) {
        return new ProductResponse(
                product.getId(),
                product.getName(),
                product.getPrice(),
                product.getCreatedAt(),
                product.getUpdatedAt());
    }
}
```

## Transaction management

### Class-level read-only with method-level write overrides

Apply `@Transactional(readOnly = true)` at class level. Override with `@Transactional` on write methods. This ensures read methods benefit from read-only optimizations (Hibernate flush mode, read replicas).

```java
@Service
@Transactional(readOnly = true)
public class OrderService {

    private final OrderRepository orderRepository;
    private final InventoryService inventoryService;
    private final NotificationService notificationService;

    public OrderService(
            OrderRepository orderRepository,
            InventoryService inventoryService,
            NotificationService notificationService) {
        this.orderRepository = orderRepository;
        this.inventoryService = inventoryService;
        this.notificationService = notificationService;
    }

    public OrderResponse findById(Long id) {
        // Runs in read-only transaction from class-level annotation
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Order not found with id: " + id));
        return toResponse(order);
    }

    @Transactional
    public OrderResponse placeOrder(CreateOrderRequest request) {
        // Overrides class-level — runs in read-write transaction
        Order order = new Order();
        order.setCustomerId(request.customerId());
        order.setStatus(OrderStatus.PENDING);

        for (OrderItemRequest item : request.items()) {
            inventoryService.reserveStock(item.productId(), item.quantity());
            order.addItem(item.productId(), item.quantity(), item.price());
        }

        Order saved = orderRepository.save(order);
        notificationService.sendOrderConfirmation(saved);
        return toResponse(saved);
    }
}
```

### Avoid self-invocation pitfall

Spring AOP proxies do not intercept internal method calls. If a `@Transactional` method calls another `@Transactional` method on the same class, the inner annotation is ignored.

```java
// WRONG — self-invocation bypasses proxy
@Service
public class PaymentService {

    @Transactional
    public void processPayment(PaymentRequest request) {
        // This internal call will NOT run in its own transaction
        saveAuditLog(request);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void saveAuditLog(PaymentRequest request) {
        // Will share the outer transaction instead of creating a new one
    }
}

// CORRECT — extract to a separate service
@Service
public class PaymentService {

    private final AuditLogService auditLogService;

    public PaymentService(AuditLogService auditLogService) {
        this.auditLogService = auditLogService;
    }

    @Transactional
    public void processPayment(PaymentRequest request) {
        // This call goes through the proxy
        auditLogService.saveAuditLog(request);
    }
}
```

## Domain exceptions

Throw domain-specific exceptions from the service layer. Never throw HTTP-related exceptions (e.g., `ResponseStatusException`) — let the global exception handler map them.

```java
package com.companyname.appname.exception;

public class ResourceNotFoundException extends RuntimeException {
    public ResourceNotFoundException(String message) {
        super(message);
    }
}

public class DuplicateResourceException extends RuntimeException {
    public DuplicateResourceException(String message) {
        super(message);
    }
}

public class BusinessRuleViolationException extends RuntimeException {
    public BusinessRuleViolationException(String message) {
        super(message);
    }
}
```

Usage in service:

```java
@Transactional
public UserResponse create(CreateUserRequest request) {
    if (userRepository.existsByEmail(request.email())) {
        throw new DuplicateResourceException("Email already registered: " + request.email());
    }
    User user = new User();
    user.setEmail(request.email());
    user.setPassword(passwordEncoder.encode(request.password()));
    User saved = userRepository.save(user);
    return toResponse(saved);
}
```

## DTO mapping

Use private helper methods for entity-to-DTO conversion. Keep mapping logic in the service — not in entities, DTOs, or separate mapper classes (unless the project uses MapStruct).

```java
// Response DTO as a record
public record ProductResponse(
        Long id,
        String name,
        BigDecimal price,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {}

// Mapping in the service
private ProductResponse toResponse(Product product) {
    return new ProductResponse(
            product.getId(),
            product.getName(),
            product.getPrice(),
            product.getCreatedAt(),
            product.getUpdatedAt());
}
```

## Service composition

For operations that span multiple domains, compose services rather than injecting repositories from other domains.

```java
@Service
@Transactional(readOnly = true)
public class CheckoutService {

    private final OrderService orderService;
    private final PaymentService paymentService;
    private final NotificationService notificationService;

    public CheckoutService(
            OrderService orderService,
            PaymentService paymentService,
            NotificationService notificationService) {
        this.orderService = orderService;
        this.paymentService = paymentService;
        this.notificationService = notificationService;
    }

    @Transactional
    public CheckoutResponse checkout(CheckoutRequest request) {
        OrderResponse order = orderService.placeOrder(request.toOrderRequest());
        PaymentResponse payment = paymentService.charge(order.id(), request.paymentMethod());
        notificationService.sendReceipt(order.id(), payment.transactionId());
        return new CheckoutResponse(order.id(), payment.transactionId());
    }
}
```