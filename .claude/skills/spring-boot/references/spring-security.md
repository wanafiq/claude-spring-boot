# Spring Security 7.x

- [Architecture](#architecture)
- [SecurityFilterChain configuration](#securityfilterchain-configuration)
- [Authentication architecture](#authentication-architecture)
- [Form login](#form-login)
- [HTTP basic](#http-basic)
- [Password storage](#password-storage)
- [UserDetailsService](#userdetailsservice)
- [Authorize HTTP requests](#authorize-http-requests)
- [Method security](#method-security)
- [OAuth2 resource server (JWT)](#oauth2-resource-server-jwt)
- [CSRF protection](#csrf-protection)
- [CORS configuration](#cors-configuration)
- [Session management](#session-management)
- [Security HTTP headers](#security-http-headers)
- [Logout](#logout)
- [Testing](#testing)

## Architecture

Spring Security's servlet support is based on Servlet Filters. Core components:

- **DelegatingFilterProxy** — bridges Servlet container lifecycle with Spring's ApplicationContext
- **FilterChainProxy** — delegates to SecurityFilterChain instances, applies HttpFirewall
- **SecurityFilterChain** — determines which filters apply to a request via RequestMatcher

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(Customizer.withDefaults())
            .httpBasic(Customizer.withDefaults())
            .formLogin(Customizer.withDefaults())
            .authorizeHttpRequests((authorize) -> authorize
                .anyRequest().authenticated()
            );
        return http.build();
    }
}
```

Filter order for the above configuration:

| Filter | Added by |
|--------|----------|
| CsrfFilter | `HttpSecurity#csrf` |
| BasicAuthenticationFilter | `HttpSecurity#httpBasic` |
| UsernamePasswordAuthenticationFilter | `HttpSecurity#formLogin` |
| AuthorizationFilter | `HttpSecurity#authorizeHttpRequests` |

### Adding custom filters

```java
// Custom filter
public class TenantFilter implements Filter {

    @Override
    public void doFilter(ServletRequest servletRequest, ServletResponse servletResponse, FilterChain filterChain) throws IOException, ServletException {
        HttpServletRequest request = (HttpServletRequest) servletRequest;
        HttpServletResponse response = (HttpServletResponse) servletResponse;

        String tenantId = request.getHeader("X-Tenant-Id");
        boolean hasAccess = isUserAllowed(tenantId);
        if (hasAccess) {
            filterChain.doFilter(request, response);
            return;
        }
        throw new AccessDeniedException("Access denied");
    }
}

// Register in chain
@Bean
SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .addFilterAfter(new TenantFilter(), AnonymousAuthenticationFilter.class);
    return http.build();
}
```

Prevent double registration when filter is also a Spring bean:

```java
@Bean
public FilterRegistrationBean<TenantFilter> tenantFilterRegistration(TenantFilter filter) {
    FilterRegistrationBean<TenantFilter> registration = new FilterRegistrationBean<>(filter);
    registration.setEnabled(false);
    return registration;
}
```

Filter placement guidelines:

| Filter type | Place after | What has already happened |
|------------|------------|--------------------------|
| Exploit protection | SecurityContextHolderFilter | SecurityContext loaded |
| Authentication | LogoutFilter | SecurityContext loaded, exploit protection |
| Authorization | AnonymousAuthenticationFilter | SecurityContext loaded, exploit protection, authenticated |

### Exception handling

`ExceptionTranslationFilter` translates `AccessDeniedException` and `AuthenticationException` into HTTP responses:

```java
try {
    filterChain.doFilter(request, response);
} catch (AccessDeniedException | AuthenticationException ex) {
    if (!authenticated || ex instanceof AuthenticationException) {
        startAuthentication(); // AuthenticationEntryPoint requests credentials
    } else {
        accessDenied(); // AccessDeniedHandler
    }
}
```

### Logging

```properties
logging.level.org.springframework.security=TRACE
```

## SecurityFilterChain configuration

### Multiple filter chains

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    @Order(1)
    public SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
        http
            .securityMatcher("/api/**")
            .authorizeHttpRequests((authorize) -> authorize
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer((oauth2) -> oauth2
                .jwt(Customizer.withDefaults())
            );
        return http.build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain webFilterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests((authorize) -> authorize
                .anyRequest().authenticated()
            )
            .formLogin(Customizer.withDefaults());
        return http.build();
    }
}
```

## Authentication architecture

### SecurityContextHolder

Stores authenticated user details. Uses `ThreadLocal` by default.

```java
// Setting authentication
SecurityContext context = SecurityContextHolder.createEmptyContext();
Authentication authentication =
    new TestingAuthenticationToken("username", "password", "ROLE_USER");
context.setAuthentication(authentication);
SecurityContextHolder.setContext(context);

// Accessing authenticated user
SecurityContext context = SecurityContextHolder.getContext();
Authentication authentication = context.getAuthentication();
String username = authentication.getName();
Object principal = authentication.getPrincipal();
Collection<? extends GrantedAuthority> authorities = authentication.getAuthorities();
```

### Authentication interface

Serves two purposes:
1. **Input to AuthenticationManager** — provides credentials (`isAuthenticated()` returns `false`)
2. **Represents authenticated user** — obtained from SecurityContext

Contains: `principal` (user identity, often UserDetails), `credentials` (password, cleared after auth), `authorities` (GrantedAuthority instances)

### AuthenticationManager and ProviderManager

```
AuthenticationManager (interface)
    └── ProviderManager (common implementation)
            └── List<AuthenticationProvider>
                    ├── DaoAuthenticationProvider (username/password)
                    ├── JwtAuthenticationProvider (JWT)
                    └── ... other providers
```

ProviderManager delegates to its list of `AuthenticationProvider` instances. Each handles a specific authentication type. Supports parent `AuthenticationManager` for fallback.

### AuthenticationEntryPoint

Sends HTTP response requesting credentials from client (redirect to login page, `WWW-Authenticate` header, etc.).

## Form login

```java
// Default (generates login page)
http.formLogin(Customizer.withDefaults());

// Custom login page
http.formLogin((form) -> form
    .loginPage("/login")
    .permitAll()
);
```

Custom login form (Thymeleaf):

```html
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:th="https://www.thymeleaf.org">
    <head><title>Please Log In</title></head>
    <body>
        <h1>Please Log In</h1>
        <div th:if="${param.error}">Invalid username and password.</div>
        <div th:if="${param.logout}">You have been logged out.</div>
        <form th:action="@{/login}" method="post">
            <div><input type="text" name="username" placeholder="Username"/></div>
            <div><input type="password" name="password" placeholder="Password"/></div>
            <input type="submit" value="Log in" />
        </form>
    </body>
</html>
```

Form requirements: POST to `/login`, CSRF token (auto-included by Thymeleaf), parameters `username` and `password`.

Controller:

```java
@Controller
class LoginController {
    @GetMapping("/login")
    String login() {
        return "login";
    }
}
```

## HTTP basic

```java
http.httpBasic(Customizer.withDefaults());
```

## Password storage

### DelegatingPasswordEncoder (default)

```java
PasswordEncoder passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
```

Storage format: `{id}encodedPassword`

```
{bcrypt}$2a$10$dXJ3SW6G7P50lGmMkkmwe.20cQQubK3.HZWzG3YB1tlRy.fqvM/BG
{noop}password
{argon2}$argon2id$...
{scrypt}$e0801$...
{pbkdf2}5d923b44a6d129f3ddf3e3c8d29412723dcbde72445e8ef6bf3b508fbf17fa4ed4d6b99ca763d8dc
```

### BCryptPasswordEncoder

```java
BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(16);
String result = encoder.encode("myPassword");
assertTrue(encoder.matches("myPassword", result));
```

### Argon2PasswordEncoder

```java
Argon2PasswordEncoder encoder = Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8();
String result = encoder.encode("myPassword");
assertTrue(encoder.matches("myPassword", result));
```

### Pbkdf2PasswordEncoder

```java
Pbkdf2PasswordEncoder encoder = Pbkdf2PasswordEncoder.defaultsForSpringSecurity_v5_8();
String result = encoder.encode("myPassword");
assertTrue(encoder.matches("myPassword", result));
```

### SCryptPasswordEncoder

```java
SCryptPasswordEncoder encoder = SCryptPasswordEncoder.defaultsForSpringSecurity_v5_8();
String result = encoder.encode("myPassword");
assertTrue(encoder.matches("myPassword", result));
```

### Password4j-based encoders (Spring Security 7.0+)

New encoders backed by Password4j: `Argon2Password4jPasswordEncoder`, `BcryptPassword4jPasswordEncoder`, `ScryptPassword4jPasswordEncoder`, `Pbkdf2Password4jPasswordEncoder`, `BalloonHashingPassword4jPasswordEncoder`.

### Compromised password checking

```java
@Bean
public CompromisedPasswordChecker compromisedPasswordChecker() {
    return new HaveIBeenPwnedRestApiPasswordChecker();
}
```

### Custom PasswordEncoder bean

```java
@Bean
public PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder();
}
```

### Change password endpoint

```java
http.passwordManagement(Customizer.withDefaults()); // redirects /.well-known/change-password to /change-password

http.passwordManagement((management) -> management
    .changePasswordPage("/update-password")
);
```

## UserDetailsService

Core interface used by `DaoAuthenticationProvider` to retrieve user details.

```java
@Bean
CustomUserDetailsService customUserDetailsService() {
    return new CustomUserDetailsService();
}
```

In-memory users (demos only):

```java
UserDetails user = User.withDefaultPasswordEncoder()
    .username("user")
    .password("password")
    .roles("USER")
    .build();
```

## Authorize HTTP requests

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .authorizeHttpRequests((authorize) -> authorize
            .dispatcherTypeMatchers(FORWARD, ERROR).permitAll()
            .requestMatchers("/static/**", "/signup", "/about").permitAll()
            .requestMatchers("/admin/**").hasRole("ADMIN")
            .requestMatchers("/db/**").hasAllAuthorities("db", "ROLE_ADMIN")
            .requestMatchers(HttpMethod.GET).hasAuthority("read")
            .requestMatchers(HttpMethod.POST).hasAuthority("write")
            .anyRequest().denyAll()
        );
    return http.build();
}
```

### Authorization rules

| Rule | Description |
|------|-------------|
| `permitAll` | No authorization required |
| `denyAll` | Always denied |
| `hasAuthority(String)` | Requires specific GrantedAuthority |
| `hasRole(String)` | Shortcut for hasAuthority with `ROLE_` prefix |
| `hasAnyAuthority(String...)` | Requires any of the given authorities |
| `hasAnyRole(String...)` | Shortcut for hasAnyAuthority with role prefix |
| `hasAllAuthorities(String...)` | Requires all given authorities |
| `hasAllRoles(String...)` | Shortcut for hasAllAuthorities with role prefix |
| `access(AuthorizationManager)` | Custom AuthorizationManager |

### Request matching

```java
// Ant pattern (default)
.requestMatchers("/resource/**").hasAuthority("USER")

// Regex
.requestMatchers(RegexRequestMatcher.regexMatcher("/resource/[A-Za-z0-9]+")).hasAuthority("USER")

// HTTP method
.requestMatchers(HttpMethod.GET).hasAuthority("read")

// Path variables
.requestMatchers("/resource/{name}").access(
    new WebExpressionAuthorizationManager("#name == authentication.name"))

// Custom matcher
RequestMatcher printview = (request) -> request.getParameter("print") != null;
.requestMatchers(printview).hasAuthority("print")
```

### PathPatternRequestMatcher with servlet path

```java
import static org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher.withDefaults;

PathPatternRequestMatcher.Builder mvc = withDefaults().basePath("/spring-mvc");
http
    .authorizeHttpRequests((authorize) -> authorize
        .requestMatchers(mvc.matcher("/admin/**")).hasAuthority("admin")
        .requestMatchers(mvc.matcher("/my/controller/**")).hasAuthority("controller")
        .anyRequest().authenticated()
    );
```

### Security matchers (filter chain scope)

```java
http
    .securityMatcher("/api/**")
    .authorizeHttpRequests((authorize) -> authorize
        .requestMatchers("/api/user/**").hasRole("USER")
        .requestMatchers("/api/admin/**").hasRole("ADMIN")
        .anyRequest().authenticated()
    );
```

### Custom AuthorizationManager (e.g. Open Policy Agent)

```java
@Component
public final class OpenPolicyAgentAuthorizationManager
        implements AuthorizationManager<RequestAuthorizationContext> {
    @Override
    public AuthorizationResult authorize(Supplier<Authentication> authentication,
            RequestAuthorizationContext context) {
        // make request to Open Policy Agent
    }
}

@Bean
SecurityFilterChain filterChain(HttpSecurity http,
        AuthorizationManager<RequestAuthorizationContext> authz) throws Exception {
    http
        .authorizeHttpRequests((authorize) -> authorize
            .anyRequest().access(authz)
        );
    return http.build();
}
```

## Method security

Requires `@EnableMethodSecurity`. Not activated by default.

```java
@EnableMethodSecurity
```

### @PreAuthorize

```java
@Component
public class BankService {
    @PreAuthorize("hasRole('ADMIN')")
    public Account readAccount(Long id) {
        // only invoked if Authentication has ROLE_ADMIN authority
    }
}
```

### @PostAuthorize

```java
@Component
public class BankService {
    @PostAuthorize("returnObject.owner == authentication.name")
    public Account readAccount(Long id) {
        // only returned if Account belongs to logged-in user
    }
}
```

### @PreFilter and @PostFilter

```java
@PreFilter("filterObject.owner == authentication.name")
public Collection<Account> updateAccounts(Account... accounts) {
    // accounts filtered to only those owned by logged-in user
}

@PostFilter("filterObject.owner == authentication.name")
public Collection<Account> readAccounts(String... ids) {
    // return value filtered to only accounts owned by logged-in user
}
```

Supported types: `Collection`, `Array`, `Map` (uses `filterObject.value`), `Stream`.

### Class-level annotations

```java
@Controller
@PreAuthorize("hasAuthority('ROLE_USER')")
public class MyController {
    @GetMapping("/endpoint")
    @PreAuthorize("hasAuthority('ROLE_ADMIN')") // overrides class-level
    public String endpoint() { ... }
}
```

### Meta-annotations

```java
@Target({ ElementType.METHOD, ElementType.TYPE })
@Retention(RetentionPolicy.RUNTIME)
@PreAuthorize("hasRole('ADMIN')")
public @interface IsAdmin {}

@Component
public class BankService {
    @IsAdmin
    public Account readAccount(Long id) { ... }
}
```

### Templating meta-annotations

```java
@Bean
static AnnotationTemplateExpressionDefaults templateExpressionDefaults() {
    return new AnnotationTemplateExpressionDefaults();
}

@Target({ ElementType.METHOD, ElementType.TYPE })
@Retention(RetentionPolicy.RUNTIME)
@PreAuthorize("hasRole('{value}')")
public @interface HasRole {
    String value();
}

@HasRole("ADMIN")
public Account readAccount(Long id) { ... }
```

### Programmatic authorization with custom bean

```java
@Component("authz")
public class AuthorizationLogic {
    public boolean decide(MethodSecurityExpressionOperations operations) {
        // authorization logic
    }
}

@PreAuthorize("@authz.decide(#root)")
public String endpoint() { ... }
```

### SpEL expressions

Common methods: `permitAll`, `denyAll`, `hasAuthority(authority)`, `hasRole(role)`, `hasAnyAuthority(...)`, `hasAnyRole(...)`, `hasAllAuthorities(...)`, `hasAllRoles(...)`, `hasPermission(object, permission)`

Fields: `authentication`, `principal`

### @AuthorizeReturnObject

```java
public class User {
    private String name;
    private String email;

    public String getName() { return this.name; }

    @PreAuthorize("hasAuthority('user:read')")
    public String getEmail() { return this.email; }
}

public class UserRepository {
    @AuthorizeReturnObject
    Optional<User> findByName(String name) { ... }
}
```

### Custom AuthorizationManager

```java
@Component
public class MyAuthorizationManager implements AuthorizationManager<MethodInvocation> {
    @Override
    public AuthorizationResult authorize(Supplier<Authentication> authentication, MethodInvocation invocation) {
        // authorization logic
    }
}

@Configuration
@EnableMethodSecurity(prePostEnabled = false)
class MethodSecurityConfig {
    @Bean
    @Role(BeanDefinition.ROLE_INFRASTRUCTURE)
    Advisor preAuthorize(MyAuthorizationManager manager) {
        return AuthorizationManagerBeforeMethodInterceptor.preAuthorize(manager);
    }
}
```

### Interceptor ordering

| Annotation | Order |
|-----------|-------|
| `@PreFilter` | 100 |
| `@PreAuthorize` | 200 |
| `@PostAuthorize` | 300 |
| `@PostFilter` | 400 |

### Role hierarchy

```java
@Bean
static MethodSecurityExpressionHandler methodSecurityExpressionHandler(RoleHierarchy roleHierarchy) {
    DefaultMethodSecurityExpressionHandler handler = new DefaultMethodSecurityExpressionHandler();
    handler.setRoleHierarchy(roleHierarchy);
    return handler;
}
```

## OAuth2 resource server (JWT)

### Minimal configuration

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://idp.example.com/issuer
```

### JwtDecoder beans

```java
// From issuer (recommended)
@Bean
public JwtDecoder jwtDecoder() {
    return JwtDecoders.fromIssuerLocation(issuer);
}

// From JWK Set URI
@Bean
public JwtDecoder jwtDecoder() {
    return NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
}

// From RSA public key
@Bean
public JwtDecoder jwtDecoder() {
    return NimbusJwtDecoder.withPublicKey(this.key).build();
}

// From symmetric key
@Bean
public JwtDecoder jwtDecoder() {
    return NimbusJwtDecoder.withSecretKey(this.key).build();
}
```

### RSA public key via Spring Boot

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          public-key-location: classpath:my-key.pub
```

### DSL configuration

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .authorizeHttpRequests((authorize) -> authorize
            .anyRequest().authenticated()
        )
        .oauth2ResourceServer((oauth2) -> oauth2
            .jwt((jwt) -> jwt
                .jwkSetUri("https://idp.example.com/.well-known/jwks.json")
            )
        );
    return http.build();
}
```

### Scope-based authorization

```java
import static org.springframework.security.oauth2.core.authorization.OAuth2AuthorizationManagers.hasScope;

http
    .authorizeHttpRequests((authorize) -> authorize
        .requestMatchers("/contacts/**").access(hasScope("contacts"))
        .requestMatchers("/messages/**").access(hasScope("messages"))
        .anyRequest().authenticated()
    )
    .oauth2ResourceServer((oauth2) -> oauth2
        .jwt(Customizer.withDefaults())
    );
```

### Custom authorities extraction

```java
@Bean
public JwtAuthenticationConverter jwtAuthenticationConverter() {
    JwtGrantedAuthoritiesConverter grantedAuthoritiesConverter = new JwtGrantedAuthoritiesConverter();
    grantedAuthoritiesConverter.setAuthoritiesClaimName("authorities");
    grantedAuthoritiesConverter.setAuthorityPrefix("ROLE_");

    JwtAuthenticationConverter jwtAuthenticationConverter = new JwtAuthenticationConverter();
    jwtAuthenticationConverter.setJwtGrantedAuthoritiesConverter(grantedAuthoritiesConverter);
    return jwtAuthenticationConverter;
}
```

### JWT validation

```java
// Clock skew
@Bean
JwtDecoder jwtDecoder() {
    NimbusJwtDecoder jwtDecoder = (NimbusJwtDecoder) JwtDecoders.fromIssuerLocation(issuerUri);
    OAuth2TokenValidator<Jwt> withClockSkew = new DelegatingOAuth2TokenValidator<>(
            new JwtTimestampValidator(Duration.ofSeconds(60)),
            new JwtIssuerValidator(issuerUri));
    jwtDecoder.setJwtValidator(withClockSkew);
    return jwtDecoder;
}

// Custom audience validator
OAuth2TokenValidator<Jwt> audienceValidator() {
    return new JwtClaimValidator<List<String>>(AUD, aud -> aud.contains("messaging"));
}

@Bean
JwtDecoder jwtDecoder() {
    NimbusJwtDecoder jwtDecoder = (NimbusJwtDecoder) JwtDecoders.fromIssuerLocation(issuerUri);
    OAuth2TokenValidator<Jwt> withIssuer = JwtValidators.createDefaultWithIssuer(issuerUri);
    OAuth2TokenValidator<Jwt> withAudience = new DelegatingOAuth2TokenValidator<>(withIssuer, audienceValidator());
    jwtDecoder.setJwtValidator(withAudience);
    return jwtDecoder;
}
```

### Trusted algorithms

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jws-algorithms: RS512
          jwk-set-uri: https://idp.example.org/.well-known/jwks.json
```

```java
@Bean
JwtDecoder jwtDecoder() {
    return NimbusJwtDecoder.withIssuerLocation(this.issuer)
            .jwsAlgorithm(RS512)
            .jwsAlgorithm(ES512)
            .build();
}
```

### Claim set mapping

```java
@Bean
JwtDecoder jwtDecoder() {
    NimbusJwtDecoder jwtDecoder = NimbusJwtDecoder.withIssuerLocation(issuer).build();
    MappedJwtClaimSetConverter converter = MappedJwtClaimSetConverter
            .withDefaults(Collections.singletonMap("sub", this::lookupUserIdBySub));
    jwtDecoder.setClaimSetConverter(converter);
    return jwtDecoder;
}
```

### Timeout and caching

```java
@Bean
public JwtDecoder jwtDecoder(RestTemplateBuilder builder, CacheManager cacheManager) {
    RestOperations rest = builder
            .setConnectTimeout(Duration.ofSeconds(60))
            .setReadTimeout(Duration.ofSeconds(60))
            .build();
    return NimbusJwtDecoder.withIssuerLocation(issuer)
            .restOperations(rest)
            .cache(cacheManager.getCache("jwks"))
            .build();
}
```

## CSRF protection

CSRF protection is **enabled by default** for unsafe HTTP methods (POST, PUT, DELETE, PATCH).

### Default configuration

```java
http.csrf(Customizer.withDefaults());
```

### SPA configuration

```java
http.csrf((csrf) -> csrf.spa());
```

### CookieCsrfTokenRepository (for JavaScript apps)

```java
http.csrf((csrf) -> csrf
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
);
```

Cookie name: `XSRF-TOKEN`, header name: `X-XSRF-TOKEN`, parameter name: `_csrf`.

### Ignore specific endpoints

```java
http.csrf((csrf) -> csrf
    .ignoringRequestMatchers("/api/*")
);
```

### Disable CSRF entirely

```java
http.csrf((csrf) -> csrf.disable());
```

### CSRF in Thymeleaf forms

Thymeleaf with `th:action` auto-includes CSRF token. Manual inclusion:

```html
<input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}"/>
```

### CSRF endpoint for mobile/API clients

```java
@RestController
public class CsrfController {
    @GetMapping("/csrf")
    public CsrfToken csrf(CsrfToken csrfToken) {
        return csrfToken;
    }
}
```

### Meta tags for AJAX

```html
<meta name="_csrf" content="${_csrf.token}"/>
<meta name="_csrf_header" content="${_csrf.headerName}"/>
```

```javascript
$(function () {
    var token = $("meta[name='_csrf']").attr("content");
    var header = $("meta[name='_csrf_header']").attr("content");
    $(document).ajaxSend(function(e, xhr, options) {
        xhr.setRequestHeader(header, token);
    });
});
```

## CORS configuration

CORS must be processed before Spring Security (pre-flight requests lack cookies).

### Using CorsConfigurationSource bean

```java
@Bean
UrlBasedCorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOrigins(Arrays.asList("https://example.com"));
    configuration.setAllowedMethods(Arrays.asList("GET", "POST"));
    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", configuration);
    return source;
}
```

### Using Spring MVC CORS (default when no CorsConfigurationSource bean)

```java
http.cors(Customizer.withDefaults());
```

### Per-SecurityFilterChain CORS

```java
@Bean
@Order(0)
public SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
    http
        .securityMatcher("/api/**")
        .cors((cors) -> cors.configurationSource(apiConfigurationSource()));
    return http.build();
}

@Bean
@Order(1)
public SecurityFilterChain webFilterChain(HttpSecurity http) throws Exception {
    http
        .cors((cors) -> cors.configurationSource(websiteConfigurationSource()));
    return http.build();
}
```

## Session management

### Session creation policies

```java
http.sessionManagement((session) -> session
    .sessionCreationPolicy(SessionCreationPolicy.STATELESS) // no session
);

http.sessionManagement((session) -> session
    .sessionCreationPolicy(SessionCreationPolicy.ALWAYS) // always create
);
```

### Session fixation protection

```java
http.sessionManagement((session) -> session
    .sessionFixation((fix) -> fix.newSession()) // or .changeSessionId() (default) or .migrateSession()
);
```

### Concurrent session control

```java
@Bean
public HttpSessionEventPublisher httpSessionEventPublisher() {
    return new HttpSessionEventPublisher();
}

@Bean
public SecurityFilterChain filterChain(HttpSecurity http) {
    http
        .sessionManagement((session) -> session
            .maximumSessions(1) // terminates first session on second login
        );
    return http.build();
}
```

Prevent second login instead:

```java
http.sessionManagement((session) -> session
    .maximumSessions(1)
    .maxSessionsPreventsLogin(true)
);
```

Role-based session limits:

```java
AuthorizationManager<?> isAdmin = AuthorityAuthorizationManager.hasRole("ADMIN");
http.sessionManagement((session) -> session
    .maximumSessions((authentication) ->
        isAdmin.authorize(() -> authentication, null).isGranted() ? -1 : 1
    )
);
```

### Invalid session handling

```java
http.sessionManagement((session) -> session
    .invalidSessionUrl("/invalidSession")
);
```

### Manual authentication storage

```java
private SecurityContextRepository securityContextRepository =
        new HttpSessionSecurityContextRepository();

@PostMapping("/login")
public void login(@RequestBody LoginRequest loginRequest,
                  HttpServletRequest request, HttpServletResponse response) {
    UsernamePasswordAuthenticationToken token =
        UsernamePasswordAuthenticationToken.unauthenticated(
            loginRequest.getUsername(), loginRequest.getPassword());
    Authentication authentication = authenticationManager.authenticate(token);

    SecurityContext context = securityContextHolderStrategy.createEmptyContext();
    context.setAuthentication(authentication);
    securityContextHolderStrategy.setContext(context);
    securityContextRepository.saveContext(context, request, response);
}
```

## Security HTTP headers

Spring Security includes these by default: Cache-Control, Content-Type-Options, HSTS, X-Frame-Options, X-XSS-Protection.

### Customize specific headers

```java
http.headers((headers) -> headers
    .frameOptions((frame) -> frame.sameOrigin())
);
```

### HSTS

```java
http.headers((headers) -> headers
    .httpStrictTransportSecurity((hsts) -> hsts
        .includeSubDomains(true)
        .preload(true)
        .maxAgeInSeconds(31536000)
    )
);
```

### Content Security Policy

```java
http.headers((headers) -> headers
    .contentSecurityPolicy((csp) -> csp
        .policyDirectives("script-src 'self' https://trustedscripts.example.com; object-src https://trustedplugins.example.com; report-uri /csp-report-endpoint/")
    )
);

// Report-only mode
http.headers((headers) -> headers
    .contentSecurityPolicy((csp) -> csp
        .policyDirectives("script-src 'self'")
        .reportOnly()
    )
);
```

### Permissions Policy

```java
http.headers((headers) -> headers
    .permissionsPolicy((permissions) -> permissions
        .policy("geolocation=(self)")
    )
);
```

### Referrer Policy

```java
http.headers((headers) -> headers
    .referrerPolicy((referrer) -> referrer
        .policy(ReferrerPolicy.SAME_ORIGIN)
    )
);
```

### Custom headers

```java
http.headers((headers) -> headers
    .addHeaderWriter(new StaticHeadersWriter("X-Custom-Security-Header", "header-value"))
);
```

### Disable all headers

```java
http.headers((headers) -> headers.disable());
```

### Use only specific headers

```java
http.headers((headers) -> headers
    .defaultsDisabled()
    .cacheControl(Customizer.withDefaults())
);
```

## Logout

Default: GET `/logout` shows confirmation, POST `/logout` performs logout.

### Default operations on POST /logout

1. Invalidates HTTP session
2. Clears SecurityContext
3. Cleans up RememberMe authentication
4. Clears CSRF token
5. Fires LogoutSuccessEvent
6. Redirects to `/login?logout`

### Configuration

```java
// Custom logout URL
http.logout((logout) -> logout.logoutUrl("/my/logout/uri"));

// Custom success URL
http.logout((logout) -> logout
    .logoutSuccessUrl("/my/success/endpoint")
    .permitAll()
);

// Delete cookies
http.logout((logout) -> logout.deleteCookies("our-custom-cookie"));

// Return status code instead of redirect (APIs)
http.logout((logout) -> logout
    .logoutSuccessHandler(new HttpStatusReturningLogoutSuccessHandler())
);
```

### Clear-Site-Data header

```java
HeaderWriterLogoutHandler clearSiteData = new HeaderWriterLogoutHandler(
    new ClearSiteDataHeaderWriter(Directive.ALL));
http.logout((logout) -> logout.addLogoutHandler(clearSiteData));
```

### Custom logout endpoint (Spring MVC)

```java
SecurityContextLogoutHandler logoutHandler = new SecurityContextLogoutHandler();

@PostMapping("/my/logout")
public String performLogout(Authentication authentication,
                           HttpServletRequest request,
                           HttpServletResponse response) {
    this.logoutHandler.logout(request, response, authentication);
    return "redirect:/home";
}
```

## Testing

### MockMvc setup

```java
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.*;

@ExtendWith(SpringExtension.class)
@ContextConfiguration(classes = SecurityConfig.class)
@WebAppConfiguration
public class SecurityTests {

    @Autowired
    private WebApplicationContext context;

    private MockMvc mvc;

    @BeforeEach
    public void setup() {
        mvc = MockMvcBuilders
                .webAppContextSetup(context)
                .apply(springSecurity())
                .build();
    }
}
```

### @WithMockUser

```java
@Test
@WithMockUser
public void requestWithDefaultUser() throws Exception {
    mvc.perform(get("/")).andExpect(status().isOk());
}

@Test
@WithMockUser(roles = "ADMIN")
public void requestWithAdmin() throws Exception {
    mvc.perform(get("/admin")).andExpect(status().isOk());
}

@Test
@WithMockUser(username = "admin", password = "pass", roles = {"USER", "ADMIN"})
public void requestWithCustomUser() throws Exception {
    mvc.perform(get("/admin")).andExpect(status().isOk());
}
```

### RequestPostProcessor approach

```java
mvc.perform(get("/").with(user("user")));
mvc.perform(get("/admin").with(user("admin").password("pass").roles("USER", "ADMIN")));
mvc.perform(get("/").with(user(userDetails)));
mvc.perform(get("/").with(anonymous()));
mvc.perform(get("/").with(authentication(authentication)));
```

### Default user for all tests

```java
mvc = MockMvcBuilders
        .webAppContextSetup(context)
        .defaultRequest(get("/").with(user("user").roles("ADMIN")))
        .apply(springSecurity())
        .build();
```

### CSRF in tests

```java
mvc.perform(post("/login").with(csrf())
        .param("username", "user")
        .param("password", "password"))
    .andExpect(status().is3xxRedirection());

mvc.perform(post("/login").with(csrf().useInvalidToken()))
    .andExpect(status().isForbidden());
```

### Testing method security

```java
@Autowired
BankService bankService;

@WithMockUser(roles = "ADMIN")
@Test
void readAccountWithAdminRole() {
    Account account = this.bankService.readAccount("12345678");
    // assertions
}

@WithMockUser(roles = "WRONG")
@Test
void readAccountWithWrongRole() {
    assertThatExceptionOfType(AccessDeniedException.class).isThrownBy(
        () -> this.bankService.readAccount("12345678"));
}
```

### Testing authorization rules

```java
@WithMockUser(authorities = "USER")
@Test
void endpointWhenUserAuthorityThenAuthorized() {
    this.mvc.perform(get("/endpoint"))
        .andExpect(status().isOk());
}

@WithMockUser
@Test
void endpointWhenNotUserAuthorityThenForbidden() {
    this.mvc.perform(get("/endpoint"))
        .andExpect(status().isForbidden());
}

@Test
void anyWhenUnauthenticatedThenUnauthorized() {
    this.mvc.perform(get("/any"))
        .andExpect(status().isUnauthorized());
}
```

### Testing concurrent sessions

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
public class MaximumSessionsTests {

    @Autowired
    private MockMvc mvc;

    @Test
    void loginOnSecondLoginThenFirstSessionTerminated() throws Exception {
        MvcResult mvcResult = this.mvc.perform(formLogin())
                .andExpect(authenticated())
                .andReturn();
        MockHttpSession firstLoginSession = (MockHttpSession) mvcResult.getRequest().getSession();

        this.mvc.perform(get("/").session(firstLoginSession))
                .andExpect(authenticated());

        this.mvc.perform(formLogin()).andExpect(authenticated());

        this.mvc.perform(get("/").session(firstLoginSession))
                .andExpect(unauthenticated());
    }
}
```

### Testing OAuth2

```java
mvc.perform(get("/endpoint").with(jwt()));

mvc.perform(get("/endpoint").with(jwt()
    .authorities(new SimpleGrantedAuthority("SCOPE_read"))
));

mvc.perform(get("/endpoint").with(jwt()
    .jwt((jwt) -> jwt.claim("sub", "user"))
));
```