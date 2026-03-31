# Spring WebMVC REST APIs

- [Key principles](#key-principles)
- [REST Controller](#rest-controller)
- [Request DTOs with Validation](#request-dtos-with-validation)
- [Response DTOs](#response-dtos)
- [Global Exception Handler](#global-exception-handler)
- [Error response examples](#error-response-examples)
- [Custom Validation](#custom-validation)
- [RestClient for External APIs](#restclient-for-external-apis-preferred-for-sync)
- [Jackson 3](#jackson-3-spring-boot-4)
- [CORS Configuration](#cors-configuration)

## Key principles

Follow these principles when creating REST APIs with Spring Web MVC:

- For Spring Boot 4.x projects, use Jackson 3.x library instead of Jackson 2.x
- Use `tools.jackson.databind.json.JsonMapper` instead of `com.fasterxml.jackson.databind.ObjectMapper`
- Use **Jackson** for `@RequestBody` binding to Request Objects with Value Object properties
- Validate with `@Valid` annotation
- Return appropriate HTTP status codes
- Delegate to services for business logic execution
- Implement Global Exception Handler using `@RestControllerAdvice` extending `ResponseEntityExceptionHandler`
- Return `ProblemDetail` type responses (RFC 7807 compliance)
- Use `RestClient` for synchronous HTTP calls (replaces `RestTemplate`)
- Use `WebClient` only for reactive/async scenarios

## REST Controller

```java
@RestController
@RequestMapping("/api/users")
@Validated
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping
    public ResponseEntity<Page<UserResponse>> getUsers(
            @PageableDefault(size = 20, sort = "createdAt") Pageable pageable) {
        Page<UserResponse> users = userService.findAll(pageable);
        return ResponseEntity.ok(users);
    }

    @GetMapping("/{id}")
    public ResponseEntity<UserResponse> getUser(@PathVariable Long id) {
        UserResponse user = userService.findById(id);
        return ResponseEntity.ok(user);
    }

    @PostMapping
    public ResponseEntity<UserResponse> createUser(
            @Valid @RequestBody CreateUserRequest request) {
        UserResponse user = userService.create(request);
        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(user.id())
                .toUri();
        return ResponseEntity.created(location).body(user);
    }

    @PutMapping("/{id}")
    public ResponseEntity<UserResponse> updateUser(
            @PathVariable Long id,
            @Valid @RequestBody UpdateUserRequest request) {
        UserResponse user = userService.update(id, request);
        return ResponseEntity.ok(user);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteUser(@PathVariable Long id) {
        userService.delete(id);
    }
}
```

## Request DTOs with Validation

```java
public record CreateUserRequest(
    @NotBlank(message = "Email is required")
    @Email(message = "Email must be valid")
    String email,

    @NotBlank(message = "Password is required")
    @Size(min = 8, max = 100, message = "Password must be 8-100 characters")
    @Pattern(regexp = "^(?=.*[A-Z])(?=.*[a-z])(?=.*\\d).*$",
             message = "Password must contain uppercase, lowercase, and digit")
    String password,

    @NotBlank(message = "Username is required")
    @Size(min = 3, max = 50)
    @Pattern(regexp = "^[a-zA-Z0-9_]+$", message = "Username must be alphanumeric")
    String username,

    @Min(value = 18, message = "Must be at least 18")
    @Max(value = 120, message = "Must be at most 120")
    Integer age
) {}

public record UpdateUserRequest(
    @Email(message = "Email must be valid")
    String email,

    @Size(min = 3, max = 50)
    String username
) {}
```

## Response DTOs

Response DTOs are plain records with no mapping logic. Keep entity-to-DTO mapping in the service layer (see [spring-service-layer.md](spring-service-layer.md)).

```java
public record UserResponse(
    Long id,
    String email,
    String username,
    Integer age,
    Boolean active,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
```

## Global Exception Handler

Create a centralized exception handler that returns **ProblemDetail** responses (RFC 7807).

Key principles:
- Use `@RestControllerAdvice` and extend `ResponseEntityExceptionHandler`
- Return `ProblemDetail` for standardized error responses
- Map different exceptions to appropriate HTTP status codes
- Include validation errors in response
- Hide internal details in production

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.support.DefaultMessageSourceResolvable;
import org.springframework.core.env.Environment;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;

import static org.springframework.http.HttpStatus.*;

@RestControllerAdvice
class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private final Environment environment;

    GlobalExceptionHandler(Environment environment) {
        this.environment = environment;
    }

    @Override
    public ResponseEntity<Object> handleMethodArgumentNotValid(
            MethodArgumentNotValidException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        log.error("Validation error", ex);
        var errors = ex.getAllErrors().stream()
                .map(DefaultMessageSourceResolvable::getDefaultMessage)
                .toList();

        ProblemDetail problemDetail = ProblemDetail.forStatusAndDetail(BAD_REQUEST, ex.getMessage());
        problemDetail.setTitle("Validation Error");
        problemDetail.setProperty("errors", errors);
        problemDetail.setProperty("timestamp", Instant.now());
        return ResponseEntity.status(UNPROCESSABLE_ENTITY).body(problemDetail);
    }

    @ExceptionHandler(DomainException.class)
    public ProblemDetail handle(DomainException exception) {
        log.warn("Bad request", exception);
        ProblemDetail problemDetail = ProblemDetail.forStatusAndDetail(BAD_REQUEST, exception.getMessage());
        problemDetail.setTitle("Bad Request");
        problemDetail.setProperty("errors", List.of(exception.getMessage()));
        problemDetail.setProperty("timestamp", Instant.now());
        return problemDetail;
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handle(ResourceNotFoundException exception) {
        log.error("Resource not found", exception);
        ProblemDetail problemDetail = ProblemDetail.forStatusAndDetail(NOT_FOUND, exception.getMessage());
        problemDetail.setTitle("Resource Not Found");
        problemDetail.setProperty("errors", List.of(exception.getMessage()));
        problemDetail.setProperty("timestamp", Instant.now());
        return problemDetail;
    }

    @ExceptionHandler(Exception.class)
    ProblemDetail handleUnexpected(Exception exception) {
        log.error("Unexpected exception occurred", exception);

        String message = "An unexpected error occurred";
        if (isDevelopmentMode()) {
            message = exception.getMessage();
        }

        ProblemDetail problemDetail = ProblemDetail.forStatusAndDetail(INTERNAL_SERVER_ERROR, message);
        problemDetail.setProperty("timestamp", Instant.now());
        return problemDetail;
    }

    private boolean isDevelopmentMode() {
        List<String> profiles = Arrays.asList(environment.getActiveProfiles());
        return profiles.contains("dev") || profiles.contains("local");
    }
}
```

## Error Response Examples

**Validation Error (400):**
```json
{
  "type": "about:blank",
  "title": "Validation Error",
  "status": 400,
  "detail": "Validation failed for argument...",
  "errors": [
    "Title is required",
    "Email must be valid"
  ]
}
```

**Domain Exception (400):**
```json
{
  "type": "about:blank",
  "title": "Bad Request",
  "status": 400,
  "detail": "Cannot update user details",
  "errors": [
    "Email is already exist"
  ]
}
```

**Resource Not Found (404):**
```json
{
  "type": "about:blank",
  "title": "Resource Not Found",
  "status": 404,
  "detail": "User not found with id: ABC123",
  "errors": [
    "User not found with id: ABC123"
  ]
}
```

**Internal Server Error (500):**
```json
{
  "type": "about:blank",
  "title": "Internal Server Error",
  "status": 500,
  "detail": "An unexpected error occurred",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Custom Validation

```java
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = UniqueEmailValidator.class)
public @interface UniqueEmail {
    String message() default "Email already exists";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

@Component
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository userRepository;

    public UniqueEmailValidator(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null) return true;
        return !userRepository.existsByEmail(email);
    }
}
```

## RestClient for External APIs (Preferred for Sync)

> **Spring Boot 4**: Use `RestClient` for synchronous HTTP calls (replaces `RestTemplate`). Use `WebClient` only for reactive/async scenarios.

```java
@Configuration
public class RestClientConfig {

    @Bean
    public RestClient restClient(RestClient.Builder builder) {
        return builder
            .baseUrl("https://api.example.com")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .build();
    }
}

@Service
public class ExternalApiService {

    private final RestClient restClient;

    public ExternalApiService(RestClient restClient) {
        this.restClient = restClient;
    }

    public ExternalDataResponse fetchData(String id) {
        return restClient
            .get()
            .uri("/data/{id}", id)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, (request, response) -> {
                throw new ResourceNotFoundException("External resource not found");
            })
            .onStatus(HttpStatusCode::is5xxServerError, (request, response) -> {
                throw new ServiceUnavailableException("External service unavailable");
            })
            .body(ExternalDataResponse.class);
    }
}
```

## Jackson 3 (Spring Boot 4)

> **Spring Boot 4** uses Jackson 3. Packages move from `com.fasterxml.jackson` to `tools.jackson` (annotations stay unchanged). `ObjectMapper` is replaced by immutable `JsonMapper`. Exceptions are now unchecked (`JacksonException` extends `RuntimeException`).

### JsonMapper Configuration

```java
@Configuration
public class JacksonConfig {

    @Bean
    public JsonMapperBuilderCustomizer jsonMapperCustomizer() {
        return builder -> builder
            .enable(SerializationFeature.INDENT_OUTPUT)
            .serializationInclusion(JsonInclude.Include.NON_NULL);
    }
}
```

### Custom Serializer/Deserializer

```java
@JacksonComponent
public class MoneySerializer extends ValueSerializer<Money> {

    @Override
    public void serialize(Money value, JsonGenerator generator,
            SerializationContext context) throws IOException {
        generator.writeString(value.getAmount().toPlainString() + " " + value.getCurrency());
    }
}

@JacksonComponent
public class MoneyDeserializer extends ValueDeserializer<Money> {

    @Override
    public Money deserialize(JsonParser parser, DeserializationContext context)
            throws IOException {
        String[] parts = parser.getString().split(" ");
        return new Money(new BigDecimal(parts[0]), Currency.getInstance(parts[1]));
    }
}
```

### Key Renames

| Jackson 2.x / Spring Boot 3 | Jackson 3.x / Spring Boot 4 |
|------------------------------|------------------------------|
| `ObjectMapper` | `JsonMapper` (immutable, use builder) |
| `JsonSerializer<T>` | `ValueSerializer<T>` |
| `JsonDeserializer<T>` | `ValueDeserializer<T>` |
| `SerializerProvider` | `SerializationContext` |
| `Module` | `JacksonModule` |
| `JsonProcessingException` | `JacksonException` (unchecked) |
| `JsonMappingException` | `DatabindException` |
| `@JsonComponent` | `@JacksonComponent` |
| `@JsonMixin` | `@JacksonMixin` |
| `Jackson2ObjectMapperBuilderCustomizer` | `JsonMapperBuilderCustomizer` |

### Changed Defaults

| Setting | 2.x | 3.x |
|---------|-----|-----|
| `FAIL_ON_UNKNOWN_PROPERTIES` | `true` | `false` |
| `SORT_PROPERTIES_ALPHABETICALLY` | `false` | `true` |
| Date serialization | timestamps | ISO-8601 |
| Enum read/write | `name()` | `toString()` |

> Use `spring.jackson.use-jackson2-defaults=true` to restore 2.x behavior during migration.

### Modules Merged into jackson-databind

No longer separate dependencies: `jackson-module-parameter-names`, `jackson-datatype-jdk8`, `jackson-datatype-jsr310`.

## CORS Configuration

```java
@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
            .allowedOrigins("http://localhost:3000", "https://example.com")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600);
    }
}
```

## Quick Reference

| Annotation | Purpose |
|------------|---------|
| `@RestController` | Marks class as REST controller (combines @Controller + @ResponseBody) |
| `@RequestMapping` | Maps HTTP requests to handler methods |
| `@GetMapping/@PostMapping` | HTTP method-specific mappings |
| `@PathVariable` | Extracts values from URI path |
| `@RequestParam` | Extracts query parameters |
| `@RequestBody` | Binds request body to method parameter |
| `@Valid` | Triggers validation on request body |
| `@RestControllerAdvice` | Global exception handling for REST controllers |
| `@ResponseStatus` | Sets HTTP status code for method |