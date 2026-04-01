# Spring Boot Testing

- [Key principles](#key-principles)
- [Test dependencies](#test-dependencies)
- [Testcontainers setup](#testcontainers-setup)
- [Unit tests](#unit-tests)
- [Integration tests](#integration-tests)
- [End-to-end tests](#end-to-end-tests)
- [Slice tests](#slice-tests)
- [Architecture tests](#architecture-tests)
- [Test utilities](#test-utilities)

## Key principles

| Test type | Scope | Annotation | Speed |
|-----------|-------|------------|-------|
| **Unit** | Single class, no Spring context | `@ExtendWith(MockitoExtension.class)` | Fast |
| **Integration** | Full app context + real dependencies | `@SpringBootTest(RANDOM_PORT)` | Slow |
| **End-to-End** | Full app + external services | `@SpringBootTest(RANDOM_PORT)` + Testcontainers | Slowest |
| **Slice** | Specific layer only | `@WebMvcTest`, `@DataJpaTest`, `@JsonTest` | Medium |
| **Architecture** | Package structure + dependency rules | ArchUnit | Fast |

General guidelines:
- Use `@MockitoBean` to mock dependencies (replaces deprecated `@MockBean`)
- Use `@MockitoSpyBean` to spy on real beans (replaces deprecated `@SpyBean`)
- Use Testcontainers with `@ServiceConnection` for databases and external services
- Use `@Sql` for test data setup with SQL scripts
- Use `test` profile and `application-test.properties` for test-specific configuration
- Use AssertJ for all assertions — it ships with `spring-boot-starter-test`

## Test dependencies

```xml
<dependencies>
    <!-- Core test starter (JUnit 5, AssertJ, Mockito, Hamcrest, JSONassert, Awaitility) -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <!-- MockMvcTester for web layer testing -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-webmvc-test</artifactId>
        <scope>test</scope>
    </dependency>
    <!-- Testcontainers support -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-testcontainers</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers-junit-jupiter</artifactId>
        <scope>test</scope>
    </dependency>
    <!-- Database-specific Testcontainers module -->
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers-postgresql</artifactId>
        <scope>test</scope>
    </dependency>
    <!-- ArchUnit for architecture tests -->
    <dependency>
        <groupId>com.tngtech.archunit</groupId>
        <artifactId>archunit-junit5</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>
```

**IMPORTANT:** Use Testcontainers 2.x coordinates:
- `org.testcontainers:testcontainers-junit-jupiter` (not `junit-jupiter`)
- `org.testcontainers:testcontainers-postgresql` (not `postgresql`)
- `org.testcontainers.postgresql.PostgreSQLContainer` (not `org.testcontainers.containers.PostgreSQLContainer`)

## Testcontainers setup

### TestcontainersConfig.java

```java
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfig {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>("postgres:18-alpine");
    }

    @Bean
    @ServiceConnection(name = "redis")
    GenericContainer<?> redisContainer() {
        return new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
                .withExposedPorts(6379);
    }
}
```

`@ServiceConnection` automatically creates `ConnectionDetails` beans — no manual property registration needed.

### DynamicPropertyRegistrar (for unsupported services)

```java
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfig {

    static GenericContainer<?> mailpit =
            new GenericContainer<>("axllent/mailpit:latest").withExposedPorts(1025);

    static {
        mailpit.start();
    }

    @Bean
    DynamicPropertyRegistrar mailProperties() {
        return registry -> {
            registry.add("spring.mail.host", mailpit::getHost);
            registry.add("spring.mail.port", mailpit::getFirstMappedPort);
        };
    }
}
```

---

## Unit tests

Test a single class in isolation — no Spring context, no database, no HTTP.

### Service unit test

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @InjectMocks
    private UserService userService;

    @Test
    void shouldCreateUser() {
        var request = new CreateUserRequest("test@example.com", "Password123", "testuser");
        var user = new User();
        user.setId(1L);
        user.setEmail(request.email());
        user.setUsername(request.username());

        when(userRepository.existsByEmail(request.email())).thenReturn(false);
        when(passwordEncoder.encode(request.password())).thenReturn("encodedPassword");
        when(userRepository.save(any(User.class))).thenReturn(user);

        var response = userService.create(request);

        assertThat(response).isNotNull();
        assertThat(response.email()).isEqualTo(request.email());
        verify(userRepository).save(any(User.class));
    }

    @Test
    void shouldThrowWhenEmailAlreadyExists() {
        var request = new CreateUserRequest("taken@example.com", "Password123", "testuser");

        when(userRepository.existsByEmail(request.email())).thenReturn(true);

        assertThatThrownBy(() -> userService.create(request))
                .isInstanceOf(DuplicateResourceException.class)
                .hasMessageContaining("Email already registered");

        verify(userRepository, never()).save(any(User.class));
    }
}
```

### Domain model unit test

```java
class OrderTest {

    @Test
    void shouldCalculateTotal() {
        var order = new Order();
        order.addItem(new OrderItem("Widget", new BigDecimal("10.00"), 3));
        order.addItem(new OrderItem("Gadget", new BigDecimal("25.00"), 1));

        assertThat(order.getTotal()).isEqualByComparingTo(new BigDecimal("55.00"));
    }

    @Test
    void shouldNotAllowNegativeQuantity() {
        assertThatThrownBy(() -> new OrderItem("Widget", new BigDecimal("10.00"), -1))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
```

---

## Integration tests

Test the full application context with real HTTP server and real dependencies (databases via Testcontainers).

### BaseIT.java

```java
import static org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT;

@SpringBootTest(webEnvironment = RANDOM_PORT)
@Import(TestcontainersConfig.class)
@AutoConfigureRestTestClient
@Sql("/test-data.sql")
public abstract class BaseIT {

    @Autowired
    protected RestTestClient restTestClient;

    @Autowired
    protected JsonMapper jsonMapper;
}
```

### REST API integration test

```java
class UserControllerIT extends BaseIT {

    @Test
    void shouldCreateUserSuccessfully() {
        var response = restTestClient
                .post()
                .uri("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .body("""
                        {
                          "fullName": "User123",
                          "email": "user123@gmail.com",
                          "password": "Secret@121212"
                        }
                        """)
                .exchange()
                .expectStatus()
                .isCreated()
                .returnResult(UserResponse.class)
                .getResponseBody();

        assertThat(response).isNotNull();
        assertThat(response.email()).isEqualTo("user123@gmail.com");
    }

    @ParameterizedTest
    @CsvSource({
        ",user1@gmail.com,password123,FullName",
        "user1,,password123,Email",
        "user1,user1@gmail.com,,Password",
    })
    void shouldRejectMissingRequiredFields(String fullName, String email,
                                           String password, String errorFieldName) {
        record RequestBody(String fullName, String email, String password) {}

        restTestClient
                .post()
                .uri("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .body(new RequestBody(fullName, email, password))
                .exchange()
                .expectStatus()
                .isBadRequest();
    }

    @Test
    void shouldNotCreateUserWithDuplicateEmail() {
        restTestClient
                .post()
                .uri("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .body("""
                        {
                          "fullName": "New User",
                          "email": "existing@gmail.com",
                          "password": "Secret@121212"
                        }
                        """)
                .exchange()
                .expectStatus()
                .isBadRequest();
    }
}
```

### Security integration test

```java
class SecuredEndpointIT extends BaseIT {

    @Test
    void shouldRequireAuthentication() {
        restTestClient
                .get()
                .uri("/api/users/me")
                .exchange()
                .expectStatus()
                .isUnauthorized();
    }

    @Test
    void shouldAllowAuthenticatedAccess() {
        restTestClient
                .get()
                .uri("/api/users/me")
                .headers(headers -> headers.setBearerAuth(getValidToken()))
                .exchange()
                .expectStatus()
                .isOk();
    }

    @Test
    void shouldForbidNonAdminAccess() {
        restTestClient
                .delete()
                .uri("/api/users/1")
                .headers(headers -> headers.setBearerAuth(getUserToken()))
                .exchange()
                .expectStatus()
                .isForbidden();
    }
}
```

### RestTestClient with AssertJ

```java
@Test
void shouldReturnUserWithAssertJ() {
    var spec = restTestClient.get().uri("/api/users/1").exchange();
    var response = RestTestClientResponse.from(spec);
    assertThat(response)
            .hasStatusOk()
            .bodyText().contains("user1@gmail.com");
}
```

---

## End-to-end tests

Full stack tests verifying complete user workflows across multiple endpoints and services.

### E2E workflow test

```java
class OrderWorkflowE2ETest extends BaseIT {

    @Test
    void shouldCompleteFullOrderWorkflow() {
        // Step 1: Create a user
        var createUserResponse = restTestClient
                .post()
                .uri("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .body("""
                        {
                          "fullName": "E2E User",
                          "email": "e2e@gmail.com",
                          "password": "Secret@121212"
                        }
                        """)
                .exchange()
                .expectStatus().isCreated()
                .returnResult(UserResponse.class)
                .getResponseBody();

        assertThat(createUserResponse).isNotNull();

        // Step 2: Authenticate
        var loginResponse = restTestClient
                .post()
                .uri("/api/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .body("""
                        {
                          "email": "e2e@gmail.com",
                          "password": "Secret@121212"
                        }
                        """)
                .exchange()
                .expectStatus().isOk()
                .returnResult(LoginResponse.class)
                .getResponseBody();

        String token = loginResponse.token();

        // Step 3: Place an order
        var orderResponse = restTestClient
                .post()
                .uri("/api/orders")
                .headers(headers -> headers.setBearerAuth(token))
                .contentType(MediaType.APPLICATION_JSON)
                .body("""
                        {
                          "items": [
                            { "productId": 1, "quantity": 2 }
                          ]
                        }
                        """)
                .exchange()
                .expectStatus().isCreated()
                .returnResult(OrderResponse.class)
                .getResponseBody();

        assertThat(orderResponse.status()).isEqualTo("PENDING");

        // Step 4: Verify order appears in user's orders
        restTestClient
                .get()
                .uri("/api/orders/{id}", orderResponse.id())
                .headers(headers -> headers.setBearerAuth(token))
                .exchange()
                .expectStatus().isOk();
    }
}
```

### Async workflow test with Awaitility

```java
@Test
void shouldProcessOrderAsynchronously() {
    // Place order
    var order = restTestClient
            .post()
            .uri("/api/orders")
            .headers(headers -> headers.setBearerAuth(getValidToken()))
            .contentType(MediaType.APPLICATION_JSON)
            .body("""
                    { "items": [{ "productId": 1, "quantity": 1 }] }
                    """)
            .exchange()
            .expectStatus().isCreated()
            .returnResult(OrderResponse.class)
            .getResponseBody();

    // Wait for async processing to complete
    await().atMost(Duration.ofSeconds(10))
            .pollInterval(Duration.ofMillis(500))
            .untilAsserted(() -> {
                var spec = restTestClient
                        .get()
                        .uri("/api/orders/{id}", order.id())
                        .headers(headers -> headers.setBearerAuth(getValidToken()))
                        .exchange();
                var response = RestTestClientResponse.from(spec);
                assertThat(response).hasStatusOk();
                assertThat(response.bodyText()).contains("COMPLETED");
            });
}
```

---

## Slice tests

Test a specific application layer in isolation — only auto-configures relevant beans.

### @WebMvcTest — Controller slice

```java
@WebMvcTest(UserController.class)
class UserControllerSliceTest {

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private UserService userService;

    @Test
    void shouldGetUser() {
        given(userService.findById(1L))
                .willReturn(new UserResponse(1L, "user@example.com", "user1"));

        assertThat(mvc.get().uri("/api/users/1")
                .accept(MediaType.APPLICATION_JSON))
                .hasStatusOk()
                .hasBodyTextEqualTo("""
                        {"id":1,"email":"user@example.com","username":"user1"}""");
    }

    @Test
    void shouldReturnBadRequestForInvalidInput() {
        assertThat(mvc.post().uri("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        { "email": "invalid", "password": "short" }
                        """))
                .hasStatus(HttpStatus.BAD_REQUEST);
    }
}
```

**Auto-configured by `@WebMvcTest`:** `@Controller`, `@ControllerAdvice`, `@JacksonComponent`, `Converter`, `Filter`, `HandlerInterceptor`, `WebMvcConfigurer`

### @WebMvcTest — Webapp (Thymeleaf) controller

```java
@WebMvcTest(UserWebController.class)
class UserWebControllerTest {

    @Autowired
    private MockMvcTester mockMvc;

    @MockitoBean
    private UserService userService;

    @Test
    void shouldRenderUserPage() {
        given(userService.findById(1L))
                .willReturn(new User(1L, "Siva", "siva@gmail.com"));

        var result = mockMvc.get().uri("/users/1").exchange();
        assertThat(result)
                .hasStatusOk()
                .hasViewName("user")
                .model().containsKey("user");
    }

    @Test
    void shouldCreateUserAndRedirect() {
        var result = mockMvc.post().uri("/users")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .param("name", "Test User")
                .param("email", "test@gmail.com")
                .param("password", "secret123")
                .exchange();
        assertThat(result)
                .hasStatus(HttpStatus.FOUND)
                .hasRedirectedUrl("/users")
                .flash().containsKey("successMessage");
    }

    @Test
    void shouldShowValidationErrors() {
        var result = mockMvc.post().uri("/users")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .param("name", "")
                .param("email", "invalid")
                .exchange();
        assertThat(result)
                .model()
                .extractingBindingResult("user")
                .hasFieldErrors("name", "email");
    }
}
```

### @DataJpaTest — Repository slice

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(TestcontainersConfig.class)
class UserRepositoryTest {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void shouldFindUserByEmail() {
        var user = new User();
        user.setEmail("test@example.com");
        user.setPassword("password");
        user.setUsername("testuser");
        entityManager.persistAndFlush(user);

        var found = userRepository.findByEmail("test@example.com");

        assertThat(found).isPresent();
        assertThat(found.get().getEmail()).isEqualTo("test@example.com");
    }

    @Test
    void shouldReturnEmptyForNonExistentEmail() {
        var found = userRepository.findByEmail("nonexistent@example.com");
        assertThat(found).isEmpty();
    }
}
```

### @JsonTest — Serialization slice

```java
@JsonTest
class UserResponseJsonTest {

    @Autowired
    private JacksonTester<UserResponse> json;

    @Test
    void shouldSerialize() throws Exception {
        var user = new UserResponse(1L, "test@example.com", "testuser");

        assertThat(json.write(user))
                .hasJsonPathStringValue("@.email")
                .extractingJsonPathStringValue("@.email")
                .isEqualTo("test@example.com");
    }

    @Test
    void shouldDeserialize() throws Exception {
        String content = """
                {"id":1,"email":"test@example.com","username":"testuser"}
                """;

        assertThat(json.parse(content))
                .isEqualTo(new UserResponse(1L, "test@example.com", "testuser"));
    }
}
```

---

## Architecture tests

Use ArchUnit to enforce package structure and dependency rules.

```java
@AnalyzeClasses(
        packages = "com.companyname.appname",
        importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest
    static final ArchRule controllersShouldNotAccessRepositories =
            noClasses()
                    .that().resideInAPackage("..controller..")
                    .should().accessClassesThat()
                    .resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule servicesShouldNotAccessControllers =
            noClasses()
                    .that().resideInAPackage("..service..")
                    .should().accessClassesThat()
                    .resideInAPackage("..controller..");

    @ArchTest
    static final ArchRule repositoriesShouldOnlyBeAccessedByServices =
            classes()
                    .that().resideInAPackage("..repository..")
                    .should().onlyBeAccessed()
                    .byAnyPackage("..service..", "..repository..");

    @ArchTest
    static final ArchRule controllersShouldBeAnnotated =
            classes()
                    .that().resideInAPackage("..controller..")
                    .and().haveSimpleNameEndingWith("Controller")
                    .should().beAnnotatedWith(RestController.class)
                    .orShould().beAnnotatedWith(Controller.class);

    @ArchTest
    static final ArchRule noFieldInjection =
            noFields()
                    .should().beAnnotatedWith(Autowired.class)
                    .because("Use constructor injection instead of field injection");
}
```

---

## Test utilities

### OutputCaptureExtension — Capture console output

```java
@ExtendWith(OutputCaptureExtension.class)
class MyLoggingTest {

    @Test
    void shouldLogOrderCreation(CapturedOutput output) {
        orderService.create(request);
        assertThat(output).contains("Order created");
    }
}
```

### TestPropertyValues — Override properties in tests

```java
@Test
void shouldUseCustomProperty() {
    var environment = new MockEnvironment();
    TestPropertyValues.of("app.feature.enabled=true").applyTo(environment);
    assertThat(environment.getProperty("app.feature.enabled")).isEqualTo("true");
}
```

### @TestConfiguration — Test-specific beans

```java
@SpringBootTest
@Import(MyTests.TestConfig.class)
class MyTests {

    @TestConfiguration
    static class TestConfig {
        @Bean
        public Clock fixedClock() {
            return Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneId.of("UTC"));
        }
    }
}
```

### application-test.properties

```yaml
# application-test.yml
spring:
  jpa:
    hibernate:
      ddl-auto: create-drop
    show-sql: true
    properties:
      hibernate:
        format_sql: true

logging:
  level:
    org.hibernate.SQL: DEBUG
    org.hibernate.orm.jdbc.bind: TRACE
```

---

## Quick reference

| Annotation | Purpose |
|------------|---------|
| `@SpringBootTest` | Full application context integration test |
| `@WebMvcTest` | Slice test for Spring MVC controllers |
| `@DataJpaTest` | Slice test for JPA repositories |
| `@JsonTest` | Slice test for JSON serialization |
| `@AutoConfigureRestTestClient` | Configure `RestTestClient` for testing |
| `@AutoConfigureMockMvc` | Configure `MockMvc`/`MockMvcTester` for testing |
| `@MockitoBean` | Mock a bean in the Spring context |
| `@MockitoSpyBean` | Spy on a real bean in the Spring context |
| `@ServiceConnection` | Auto-configure connection from Testcontainer |
| `@Sql` | Execute SQL scripts before test |
| `@ActiveProfiles` | Activate Spring profiles for test |
| `@TestConfiguration` | Test-specific bean configuration |
| `@Import` | Import configuration classes into test context |
| `@AnalyzeClasses` | ArchUnit class analysis scope |
| `@ArchTest` | ArchUnit architecture rule |