# Spring Boot Web Application Testing with MockMvcTester

Use this reference for testing **view-rendering controllers** (Thymeleaf, form submissions, redirects).
For testing **REST API endpoints** that return JSON, see [spring-boot-rest-api-testing.md](spring-boot-rest-api-testing.md).

- [Key principles](#key-principles)
- [Setup](#setup)
- [BaseWebIT](#basewebitjava)
- [Testing view rendering controllers](#testing-the-view-rendering-controllers)

## Key principles

Follow these principles when testing Spring Boot Web MVC controllers with MockMvcTester:

- Use `MockMvcTester` for AssertJ-style fluent assertions (Spring Boot 4+)
- Use `@WebMvcTest` for slice tests that focus on a single controller with mocked services
- Use `@SpringBootTest` with `@AutoConfigureMockMvc` for integration tests with real dependencies
- Use Testcontainers for integration tests that need databases or external services
- Use `APPLICATION_FORM_URLENCODED` content type for form submissions (not JSON)

## Setup

### Dependencies

Add the following dependency:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc-test</artifactId>
    <scope>test</scope>
</dependency>
```

### Slice Test Setup (@WebMvcTest)

For testing a single controller in isolation:

```java
@WebMvcTest(controllers = UserController.class)
class UserControllerTests {

    @Autowired
    MockMvcTester mockMvc;

    @MockitoBean
    UserService userService;

    // tests...
}
```

### Integration Test Setup (@SpringBootTest)

For full integration tests:

```java
@SpringBootTest
@AutoConfigureMockMvc
class UserControllerIT {

    @Autowired
    MockMvcTester mockMvc;

    // tests...
}
```

## BaseWebIT.java

For integration tests that need Testcontainers, reuse the shared `TestcontainersConfig` from [spring-boot-rest-api-testing.md](spring-boot-rest-api-testing.md):

```java
package com.companyname.appname;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

@SpringBootTest
@AutoConfigureMockMvc
@Import(TestcontainersConfig.class)
@Sql("/test-data.sql")
public abstract class BaseWebIT {

    @Autowired
    protected MockMvcTester mockMvc;
}
```

## Basic test structure

Simple single-statement assertions:

```java
@Test
void shouldRenderHomePage() {
    assertThat(mockMvcTester.get().uri("/home"))
        .hasStatusOk();
}
```

## Testing the view rendering controllers

### Assert view name and model attributes

```java
@Test
void shouldGetUserById() {
    var result = mockMvcTester.get().uri("/users/1").exchange();
    assertThat(result)
            .hasStatusOk()
            .hasViewName("user")
            .model()
            .containsKeys("user")
            .containsEntry("user", new User(1L, "Siva", "siva@gmail.com", "siva"));
}
```

### Assert URL redirects and flash attributes

```java
@Test
void shouldCreateUserSuccessfully() {
    var result = mockMvcTester.post().uri("/users")
            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
            .param("name", "Test User 4")
            .param("email", "testuser4@gmail.com")
            .param("password", "testuser4")
            .exchange();
    assertThat(result)
            .hasStatus(HttpStatus.FOUND)
            .hasRedirectedUrl("/users")
            .flash().containsKey("successMessage")
            .hasEntrySatisfying("successMessage",
                    value -> assertThat(value).isEqualTo("User saved successfully"));
}
```

### Assert model validation errors

```java
@Test
void shouldGetErrorsWhenUserDataIsInvalid() {
   var result = mockMvcTester.post().uri("/users")
           .contentType(MediaType.APPLICATION_FORM_URLENCODED)
           .param("name", "") // blank - invalid
           .param("email", "testuser4gmail.com") // invalid email format
           .param("password", "pwd") // valid
           .exchange();
   assertThat(result)
           .model()
           .extractingBindingResult("user")
           .hasErrorsCount(2)
           .hasFieldErrors("name", "email");
}
```

### Assert authentication required

```java
@Test
void shouldRedirectToLoginWhenNotAuthenticated() {
    assertThat(mockMvcTester.get().uri("/admin/dashboard"))
            .hasStatus(HttpStatus.FOUND)
            .hasRedirectedUrl("/login");
}
```