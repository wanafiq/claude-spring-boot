# Spring Data JPA 4.x

- [Repository interfaces](#repository-interfaces)
- [Defining repositories](#defining-repositories)
- [Entity persistence](#entity-persistence)
- [Query methods](#query-methods)
- [Projections](#projections)
- [Specifications](#specifications)
- [Query by Example](#query-by-example)
- [Custom repository implementations](#custom-repository-implementations)
- [Auditing](#auditing)
- [Domain events](#domain-events)
- [Transactions](#transactions)
- [Locking](#locking)
- [Entity graphs](#entity-graphs)
- [Scrolling large results](#scrolling-large-results)

## Repository interfaces

```java
// Marker — no methods, captures domain type + ID type
interface MyRepository extends Repository<Entity, Long> {}

// Standard CRUD — returns Iterable
interface MyRepository extends CrudRepository<Entity, Long> {}

// CRUD returning List instead of Iterable (preferred)
interface MyRepository extends ListCrudRepository<Entity, Long> {}

// Pagination and sorting only (does NOT extend CrudRepository since 3.0)
interface MyRepository extends PagingAndSortingRepository<Entity, Long> {}

// Full JPA features: CRUD + paging + flush + batch delete
interface MyRepository extends JpaRepository<Entity, Long> {}
```

Since Spring Data 3.0, `PagingAndSortingRepository` no longer extends `CrudRepository`. Extend both if you need both:

```java
interface UserRepository extends ListCrudRepository<User, Long>,
                                 PagingAndSortingRepository<User, Long> {}
```

### Core CrudRepository methods

```java
<S extends T> S save(S entity);
Optional<T> findById(ID id);
Iterable<T> findAll();
long count();
void delete(T entity);
boolean existsById(ID id);
```

### Derived count and delete queries

```java
interface UserRepository extends CrudRepository<User, Long> {
    long countByLastname(String lastname);
    long deleteByLastname(String lastname);
    List<User> removeByLastname(String lastname);
}
```

## Defining repositories

### Selective method exposure

```java
@NoRepositoryBean
interface MyBaseRepository<T, ID> extends Repository<T, ID> {
    Optional<T> findById(ID id);
    <S extends T> S save(S entity);
}

interface UserRepository extends MyBaseRepository<User, Long> {
    User findByEmailAddress(String emailAddress);
}
```

### @RepositoryDefinition alternative

```java
@RepositoryDefinition(domainClass = User.class, idClass = Long.class)
interface UserRepository {
    Optional<User> findById(Long id);
    User save(User user);
}
```

### Multiple Spring Data modules

Strategy 1 — module-specific interfaces:

```java
interface PersonRepository extends JpaRepository<Person, Long> {}
```

Strategy 2 — domain class annotations:

```java
@Entity
class Person { /* JPA */ }

@Document
class User { /* MongoDB */ }
```

Strategy 3 — base package scoping:

```java
@EnableJpaRepositories(basePackages = "com.acme.repositories.jpa")
@EnableMongoRepositories(basePackages = "com.acme.repositories.mongo")
class Configuration {}
```

## Entity persistence

`CrudRepository.save(…)` delegates to JPA `EntityManager`:
- **New entity** → `entityManager.persist(…)`
- **Existing entity** → `entityManager.merge(…)`

### Entity state detection (default)

1. Check `@Version` property — if non-primitive and `null`, entity is new
2. Check `@Id` property — if `null`, entity is new

### Persistable for manual ID assignment

```java
@MappedSuperclass
public abstract class AbstractEntity<ID> implements Persistable<ID> {

    @Transient
    private boolean isNew = true;

    @Override
    public boolean isNew() {
        return isNew;
    }

    @PostPersist
    @PostLoad
    void markNotNew() {
        this.isNew = false;
    }
}
```

## Query methods

### Derived queries from method names

```java
public interface UserRepository extends JpaRepository<User, Long> {

    List<User> findByEmailAddressAndLastname(String email, String lastname);
    // → select u from User u where u.emailAddress = ?1 and u.lastname = ?2

    List<User> findByLastnameOrFirstname(String lastname, String firstname);
    List<User> findByStartDateBetween(LocalDate start, LocalDate end);
    List<User> findByAgeLessThan(int age);
    List<User> findByAgeGreaterThanEqual(int age);
    List<User> findByLastnameIgnoreCase(String lastname);
    List<User> findByFirstnameContaining(String fragment);
    List<User> findByFirstnameStartingWith(String prefix);
    List<User> findByActiveTrue();
    List<User> findByActiveFalse();
    List<User> findByLastnameNot(String lastname);
    List<User> findByAgeIn(Collection<Integer> ages);
    List<User> findByLastnameIsNull();
    List<User> findByLastnameIsNotNull();
    List<User> findByAgeOrderByLastnameDesc(int age);
    List<User> findDistinctByLastname(String lastname);
}
```

### Keyword reference

| Keyword | JPQL snippet |
|---------|-------------|
| `And` | `where x.a = ?1 and x.b = ?2` |
| `Or` | `where x.a = ?1 or x.b = ?2` |
| `Is`, `Equals` | `where x.a = ?1` |
| `Between` | `where x.a between ?1 and ?2` |
| `LessThan` / `LessThanEqual` | `< ?1` / `<= ?1` |
| `GreaterThan` / `GreaterThanEqual` | `> ?1` / `>= ?1` |
| `After` / `Before` | `> ?1` / `< ?1` |
| `IsNull` / `IsNotNull` | `is null` / `is not null` |
| `Like` / `NotLike` | `like ?1` / `not like ?1` |
| `StartingWith` | `like ?1%` |
| `EndingWith` | `like %?1` |
| `Containing` | `like %?1%` |
| `OrderBy` | `order by x.a desc` |
| `Not` | `<> ?1` |
| `In` / `NotIn` | `in ?1` / `not in ?1` |
| `True` / `False` | `= true` / `= false` |
| `IgnoreCase` | `UPPER(x.a) = UPPER(?1)` |

### @Query — JPQL

```java
@Query("select u from User u where u.emailAddress = ?1")
User findByEmailAddress(String emailAddress);

@Query("select u from User u where u.firstname like %?1")
List<User> findByFirstnameEndsWith(String firstname);
```

### @Query — named parameters

```java
@Query("select u from User u where u.firstname = :firstname or u.lastname = :lastname")
User findByLastnameOrFirstname(@Param("lastname") String lastname,
                               @Param("firstname") String firstname);
```

With `-parameters` compiler flag (Spring Data 4+), `@Param` is optional.

### @NativeQuery

```java
@NativeQuery("SELECT * FROM users WHERE email_address = ?1")
User findByEmailAddress(String emailAddress);

@NativeQuery(value = "SELECT * FROM users WHERE lastname = ?1",
             countQuery = "SELECT count(*) FROM users WHERE lastname = ?1")
Page<User> findByLastname(String lastname, Pageable pageable);
```

### Native query returning raw maps

```java
@NativeQuery("SELECT * FROM users WHERE email_address = ?1")
Map<String, Object> findRawMapByEmail(String emailAddress);

@NativeQuery("SELECT * FROM users WHERE lastname = ?1")
List<Map<String, Object>> findRawMapByLastname(String lastname);
```

### Modifying queries

```java
@Modifying
@Query("update User u set u.firstname = ?1 where u.lastname = ?2")
int setFixedFirstnameFor(String firstname, String lastname);

@Modifying
@Query("delete from User u where u.active = false")
void deleteInactiveUsers();
```

Derived `deleteByX()` loads entities and triggers lifecycle callbacks. `@Modifying @Query` issues a single bulk statement without callbacks.

### SpEL in queries

```java
// #{#entityName} resolves to the entity name — useful for inheritance
@Query("select e from #{#entityName} e where e.attribute = ?1")
List<T> findAllByAttribute(String attribute);

// Sanitize LIKE input
@Query("select u from User u where u.firstname like %?#{escape([0])}% escape ?#{escapeCharacter()}")
List<User> findContainingEscaped(String namePart);
```

### Sorting with @Query

```java
@Query("select u from User u where u.lastname like ?1%")
List<User> findByAndSort(String lastname, Sort sort);

// Safe property-based sort
repo.findByAndSort("stark", Sort.by("firstname"));

// Unsafe function-based sort
repo.findByAndSort("targaryen", JpaSort.unsafe("LENGTH(firstname)"));
```

### Query hints

```java
@QueryHints(value = { @QueryHint(name = "name", value = "value") },
            forCounting = false)
Page<User> findByLastname(String lastname, Pageable pageable);
```

### Query comments with @Meta

```java
@Meta(comment = "find roles by name")
List<Role> findByName(String name);
```

Requires `spring.jpa.properties.hibernate.use_sql_comments=true`.

### Named queries

```java
@Entity
@NamedQuery(name = "User.findByEmailAddress",
            query = "select u from User u where u.emailAddress = ?1")
public class User { }

// Repository method resolves to named query User.findByEmailAddress
public interface UserRepository extends JpaRepository<User, Long> {
    User findByEmailAddress(String emailAddress);
}
```

### Query rewriting

```java
public class MyQueryRewriter implements QueryRewriter {
    @Override
    public String rewrite(String query, Sort sort) {
        return query.replaceAll("original_alias", "rewritten_alias");
    }
}

@Query(value = "select u from User u", queryRewriter = MyQueryRewriter.class)
List<User> findByNonNativeQuery(String param);
```

## Projections

### Closed interface projection

```java
interface NamesOnly {
    String getFirstname();
    String getLastname();
}

interface PersonRepository extends Repository<Person, UUID> {
    Collection<NamesOnly> findByLastname(String lastname);
}
```

Spring Data optimizes the query to select only the required columns.

### Open interface projection

```java
interface NamesOnly {
    @Value("#{target.firstname + ' ' + target.lastname}")
    String getFullName();
}
```

Open projections require full entity materialization.

### Default method projection

```java
interface NamesOnly {
    String getFirstname();
    String getLastname();

    default String getFullName() {
        return getFirstname().concat(" ").concat(getLastname());
    }
}
```

### Class-based projection (DTO with record)

```java
record NamesOnly(String firstname, String lastname) {}

interface PersonRepository extends Repository<Person, UUID> {
    Collection<NamesOnly> findByLastname(String lastname);
}
```

Spring Data JPA auto-rewrites JPQL to constructor expressions for DTO projections.

### Nested projections

```java
interface PersonSummary {
    String getFirstname();
    String getLastname();
    AddressSummary getAddress();

    interface AddressSummary {
        String getCity();
    }
}
```

### Dynamic projections

```java
interface PersonRepository extends Repository<Person, UUID> {
    <T> Collection<T> findByLastname(String lastname, Class<T> type);
}

// Usage
Collection<Person> aggregates = people.findByLastname("Matthews", Person.class);
Collection<NamesOnly> projections = people.findByLastname("Matthews", NamesOnly.class);
```

### JPQL constructor expression

```java
@Query("SELECT new com.example.UserDto(u.firstname, u.lastname) FROM User u WHERE u.lastname = :lastname")
List<UserDto> findByLastname(String lastname);
```

## Specifications

Enable by extending `JpaSpecificationExecutor`:

```java
public interface CustomerRepository extends CrudRepository<Customer, Long>,
                                            JpaSpecificationExecutor<Customer> {}
```

### PredicateSpecification (Spring Data JPA 4.0+)

```java
public interface PredicateSpecification<T> {
    Predicate toPredicate(From<?, T> from, CriteriaBuilder builder);
}
```

```java
class CustomerSpecs {

    static PredicateSpecification<Customer> isLongTermCustomer() {
        return (from, builder) -> {
            LocalDate date = LocalDate.now().minusYears(2);
            return builder.lessThan(from.get("createdAt"), date);
        };
    }

    static PredicateSpecification<Customer> hasSalesOfMoreThan(MonetaryAmount value) {
        return (from, builder) -> builder.greaterThan(from.get("sales"), value);
    }
}
```

### Composing specifications

```java
List<Customer> customers = customerRepository.findAll(
    isLongTermCustomer().or(hasSalesOfMoreThan(amount))
);
```

### Specification (query-bound)

```java
public interface Specification<T> {
    Predicate toPredicate(Root<T> root, CriteriaQuery<?> query, CriteriaBuilder builder);
}
```

### UpdateSpecification and DeleteSpecification

```java
public interface UpdateSpecification<T> {
    Predicate toPredicate(Root<T> root, CriteriaUpdate<T> update, CriteriaBuilder builder);
}

public interface DeleteSpecification<T> {
    Predicate toPredicate(Root<T> root, CriteriaDelete<T> delete, CriteriaBuilder builder);
}
```

### Fluent API with specifications

```java
// Projected page
Page<CustomerProjection> page = repository.findBy(spec,
    q -> q.as(CustomerProjection.class)
          .page(PageRequest.of(0, 20, Sort.by("lastname"))));

// First result sorted
Optional<Customer> match = repository.findBy(spec,
    q -> q.sortBy(Sort.by("lastname").descending()).first());
```

Fluent terminal methods: `first()`, `one()`, `all()`, `page(Pageable)`, `slice(Pageable)`, `scroll(ScrollPosition)`, `stream()`, `count()`, `exists()`.

## Query by Example

```java
Person person = new Person();
person.setFirstname("Dave");

Example<Person> example = Example.of(person);
List<Person> results = personRepository.findAll(example);
```

### ExampleMatcher

```java
ExampleMatcher matcher = ExampleMatcher.matching()
    .withIgnorePaths("lastname")
    .withIncludeNullValues()
    .withStringMatcher(StringMatcher.ENDING);

Example<Person> example = Example.of(person, matcher);
```

### Per-property matchers

```java
ExampleMatcher matcher = ExampleMatcher.matching()
    .withMatcher("firstname", endsWith())
    .withMatcher("lastname", startsWith().ignoreCase());
```

### StringMatcher options

| Matcher | Behavior |
|---------|----------|
| `DEFAULT` | `firstname = ?0` |
| `EXACT` | `firstname = ?0` |
| `STARTING` | `firstname like ?0 + '%'` |
| `ENDING` | `firstname like '%' + ?0` |
| `CONTAINING` | `firstname like '%' + ?0 + '%'` |

All matchers support `.ignoreCase()`.

### Fluent API with QBE

```java
Page<CustomerProjection> page = repository.findBy(example,
    q -> q.as(CustomerProjection.class)
          .page(PageRequest.of(0, 20, Sort.by("lastname"))));
```

## Custom repository implementations

### Fragment interface pattern

```java
interface CustomizedUserRepository {
    void someCustomMethod(User user);
}

// Implementation class: interface name + "Impl" suffix
class CustomizedUserRepositoryImpl implements CustomizedUserRepository {
    @Override
    public void someCustomMethod(User user) {
        // custom implementation
    }
}

interface UserRepository extends CrudRepository<User, Long>, CustomizedUserRepository {}
```

### Multiple fragments

```java
interface UserRepository extends CrudRepository<User, Long>,
                                 HumanRepository,
                                 ContactRepository {}
```

### Reusable generic fragment

```java
interface CustomizedSave<T> {
    <S extends T> S save(S entity);
}

class CustomizedSaveImpl<T> implements CustomizedSave<T> {
    @Override
    public <S extends T> S save(S entity) { /* custom */ }
}

interface UserRepository extends CrudRepository<User, Long>, CustomizedSave<User> {}
```

### Custom base repository class

```java
class MyRepositoryImpl<T, ID> extends SimpleJpaRepository<T, ID> {

    private final EntityManager entityManager;

    MyRepositoryImpl(JpaEntityInformation entityInformation,
                     EntityManager entityManager) {
        super(entityInformation, entityManager);
        this.entityManager = entityManager;
    }

    @Override
    @Transactional
    public <S extends T> S save(S entity) {
        // custom save logic
    }
}

@Configuration
@EnableJpaRepositories(repositoryBaseClass = MyRepositoryImpl.class)
class ApplicationConfiguration {}
```

### Using JpaContext for multi-EntityManager

```java
class UserRepositoryImpl implements UserRepositoryCustom {

    private final EntityManager entityManager;

    public UserRepositoryImpl(JpaContext context) {
        this.entityManager = context.getEntityManagerByManagedType(User.class);
    }
}
```

## Auditing

### Auditable entity

```java
@Entity
@EntityListeners(AuditingEntityListener.class)
public class User {

    @CreatedBy
    private String createdBy;

    @CreatedDate
    private Instant createdDate;

    @LastModifiedBy
    private String lastModifiedBy;

    @LastModifiedDate
    private Instant lastModifiedDate;
}
```

`@CreatedDate` and `@LastModifiedDate` support: `Instant`, `LocalDateTime`, `ZonedDateTime`, `long`, `Long`, `Date`, `Calendar`.

### Auditable base class

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class AuditableEntity {

    @CreatedBy
    private String createdBy;

    @CreatedDate
    private Instant createdDate;

    @LastModifiedBy
    private String lastModifiedBy;

    @LastModifiedDate
    private Instant lastModifiedDate;
}
```

### AuditorAware with Spring Security

```java
class SpringSecurityAuditorAware implements AuditorAware<String> {

    @Override
    public Optional<String> getCurrentAuditor() {
        return Optional.ofNullable(SecurityContextHolder.getContext())
                .map(SecurityContext::getAuthentication)
                .filter(Authentication::isAuthenticated)
                .map(Authentication::getPrincipal)
                .map(User.class::cast)
                .map(User::getUsername);
    }
}
```

### Enable JPA auditing

```java
@Configuration
@EnableJpaAuditing
class AuditingConfig {

    @Bean
    public AuditorAware<String> auditorProvider() {
        return new SpringSecurityAuditorAware();
    }
}
```

## Domain events

### Using AbstractAggregateRoot

```java
class Order extends AbstractAggregateRoot<Order> {

    Order complete() {
        registerEvent(new OrderCompleted(this.id));
        return this;
    }
}
```

### Manual @DomainEvents

```java
class AnAggregateRoot {

    @DomainEvents
    Collection<Object> domainEvents() {
        // return events to publish
    }

    @AfterDomainEventPublication
    void callbackMethod() {
        // clean up event list
    }
}
```

Events are published on `save(…)`, `saveAll(…)`, `delete(…)`, `deleteAll(…)`, `deleteAllInBatch(…)`. **Not** on `deleteById(…)`.

## Transactions

### Default behavior (SimpleJpaRepository)

- Read operations: `@Transactional(readOnly = true)`
- Write operations: `@Transactional`

### Interface-level read-only with write override

```java
@Transactional(readOnly = true)
interface UserRepository extends JpaRepository<User, Long> {

    List<User> findByLastname(String lastname);

    @Modifying
    @Transactional
    @Query("delete from User u where u.active = false")
    void deleteInactiveUsers();
}
```

### Custom timeout

```java
@Override
@Transactional(timeout = 10)
List<User> findAll();
```

### readOnly = true effects

- **Hibernate**: sets flush mode to `NEVER`, skips dirty checks
- **Performance**: significant improvement on large object trees
- **Not a constraint**: does not prevent INSERT/UPDATE at the database level

Best practice: define `@Transactional` boundaries at the service layer, not repository.

## Locking

```java
interface UserRepository extends Repository<User, Long> {

    @Lock(LockModeType.PESSIMISTIC_READ)
    List<User> findByLastname(String lastname);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<User> findById(Long id);
}
```

Common lock modes: `OPTIMISTIC`, `OPTIMISTIC_FORCE_INCREMENT`, `PESSIMISTIC_READ`, `PESSIMISTIC_WRITE`, `PESSIMISTIC_FORCE_INCREMENT`.

## Entity graphs

### Named entity graph

```java
@Entity
@NamedEntityGraph(name = "GroupInfo.detail",
                  attributeNodes = @NamedAttributeNode("members"))
public class GroupInfo {
    @ManyToMany
    List<GroupMember> members = new ArrayList<>();
}

public interface GroupRepository extends CrudRepository<GroupInfo, String> {

    @EntityGraph(value = "GroupInfo.detail", type = EntityGraphType.LOAD)
    GroupInfo getByGroupName(String name);
}
```

### Ad-hoc entity graph

```java
@EntityGraph(attributePaths = { "members" })
GroupInfo getByGroupName(String name);
```

## Scrolling large results

### Offset-based scrolling

```java
interface UserRepository extends Repository<User, Long> {
    Window<User> findFirst10ByLastnameOrderByFirstname(String lastname, OffsetScrollPosition position);
}

WindowIterator<User> users = WindowIterator
    .of(position -> repository.findFirst10ByLastnameOrderByFirstname("Doe", position))
    .startingAt(OffsetScrollPosition.initial());
```

### Keyset-based scrolling

```java
interface UserRepository extends Repository<User, Long> {
    Window<User> findFirst10ByLastnameOrderByFirstname(String lastname, KeysetScrollPosition position);
}

WindowIterator<User> users = WindowIterator
    .of(position -> repository.findFirst10ByLastnameOrderByFirstname("Doe", position))
    .startingAt(ScrollPosition.keyset());
```

### Pagination

```java
Page<User> findByLastname(String lastname, Pageable pageable);

// Usage
Page<User> users = repository.findByLastname("Doe", PageRequest.of(1, 20));
```