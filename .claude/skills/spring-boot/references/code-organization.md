# Spring Boot Application Package Structure

Use a **layer-based layout**: organize packages by **technical responsibility** with clear boundaries between layers.

### Recommended Package Structure

```
com.{companyname}.{appname}/
├── Application.java                # Main Spring Boot entrypoint class
├── controller/                     # REST endpoints
│   ├── ProductController.java
│   └── OrderController.java
├── service/                        # Business logic
│   ├── ProductService.java
│   └── OrderService.java
├── repository/                     # Data access
│   ├── ProductRepository.java
│   └── OrderRepository.java
├── model/                          # JPA entities
│   ├── Product.java
│   └── Order.java
├── dto/                            # Request/Response DTOs
│   ├── ProductRequest.java
│   ├── ProductResponse.java
│   ├── OrderRequest.java
│   └── OrderResponse.java
├── config/                         # Configuration
│   ├── SecurityConfig.java
│   └── WebMvcConfig.java
└── exception/                      # Custom exceptions + handler
    ├── ResourceNotFoundException.java
    └── GlobalExceptionHandler.java
```

Explanation of the above package structure:

- **Application.java**: The main Spring Boot entry point class annotated with `@SpringBootApplication`. Contains the
  `main()` method that bootstraps the application.

- **controller/**: REST controller classes annotated with `@RestController` that handle HTTP requests, validate
  input via `@Valid`, and delegate to services.

- **service/**: Service classes annotated with `@Service` containing business logic, transaction management
  via `@Transactional`, and orchestration of repository calls. Use constructor injection only.

- **repository/**: Spring Data JPA repository interfaces extending `JpaRepository` or `CrudRepository` for data access.

- **model/**: JPA entity classes annotated with `@Entity` that map to database tables. No Lombok — write
  getters/setters explicitly.

- **dto/**: Data Transfer Objects as Java records. Request payloads (data from clients) and response payloads
  (data sent to clients). Use `@Valid` annotations for input validation.

- **config/**: Application-wide configuration classes including:
    - **SecurityConfig.java**: Spring Security 7 configuration for authentication and authorization.
    - **WebMvcConfig.java**: MVC configuration (CORS, interceptors, formatters).

- **exception/**: Custom exception classes and centralized exception handling using `@RestControllerAdvice`
  for consistent error responses.

### Layering Rules

- Controller → Service → Repository (strict direction, no skipping layers)
- Controller handles HTTP concerns, validation
- Service handles business logic, transactions
- Repository handles data persistence
- DTOs live at boundaries — never pass entities directly to controllers

### Naming Conventions

| Type              | Convention    | Example                                              |
|-------------------|---------------|------------------------------------------------------|
| **Entities**      | Domain noun   | `Product`, `Order`, `User`                           |
| **HTTP Request**  | `*Request`    | `CreateProductRequest`, `UpdateOrderRequest`         |
| **HTTP Response** | `*Response`   | `ProductResponse`, `OrderResponse`                   |
| **Repositories**  | `*Repository` | `ProductRepository`, `OrderRepository`               |
| **Services**      | `*Service`    | `ProductService`, `OrderService`                     |
| **Controllers**   | `*Controller` | `ProductController`, `OrderController`               |
| **Exceptions**    | `*Exception`  | `ResourceNotFoundException`, `InvalidOrderException` |
| **Config**        | `*Config`     | `SecurityConfig`, `WebMvcConfig`                     |
| **Test Classes**  | `*Test`       | `ProductControllerTest`, `ProductServiceTest`        |