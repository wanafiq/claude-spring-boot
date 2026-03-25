# Batch Processing - Spring Batch 6

## Job Configuration

```java
@Configuration
@EnableBatchProcessing
@EnableJdbcJobRepository(dataSourceRef = "batchDataSource")
public class BatchConfig {

    @Bean
    public Job importJob(JobRepository jobRepository, Step validateStep, Step importStep) {
        return new JobBuilder("importJob", jobRepository)
            .validator(new DefaultJobParametersValidator(
                new String[]{"inputFile"},
                new String[]{"skipLimit"}
            ))
            .incrementer(new RunIdIncrementer())
            .listener(new JobExecutionListener() {
                @Override
                public void afterJob(JobExecution jobExecution) {
                    jobExecution.getStepExecutions().forEach(step ->
                        System.out.printf("Step %s: read=%d, written=%d, skipped=%d%n",
                            step.getStepName(), step.getReadCount(),
                            step.getWriteCount(), step.getSkipCount()));
                }
            })
            .start(validateStep)
            .next(importStep)
            .build();
    }
}
```

## Chunk-Oriented Step

> The core pattern: read items one at a time, process them, then write in chunks within a transaction.

```java
@Bean
public Step importStep(JobRepository jobRepository,
                       PlatformTransactionManager transactionManager,
                       ItemReader<CustomerCsv> reader,
                       ItemProcessor<CustomerCsv, Customer> processor,
                       ItemWriter<Customer> writer) {
    return new StepBuilder("importStep", jobRepository)
        .<CustomerCsv, Customer>chunk(500)
        .transactionManager(transactionManager)
        .reader(reader)
        .processor(processor)
        .writer(writer)
        .build();
}
```

## Tasklet Step

For simple single-operation tasks (cleanup, validation, file moves).

```java
@Bean
public Step validateStep(JobRepository jobRepository,
                         PlatformTransactionManager transactionManager) {
    return new StepBuilder("validateStep", jobRepository)
        .tasklet((contribution, chunkContext) -> {
            String inputFile = chunkContext.getStepContext()
                .getJobParameters().get("inputFile").toString();

            if (!new FileSystemResource(inputFile).exists()) {
                throw new IllegalArgumentException("Input file not found: " + inputFile);
            }
            return RepeatStatus.FINISHED;
        }, transactionManager)
        .build();
}
```

## ItemReader Implementations

### FlatFileItemReader (CSV)

```java
@Bean
@StepScope
public FlatFileItemReader<CustomerCsv> csvReader(
        @Value("#{jobParameters['inputFile']}") Resource resource) {
    return new FlatFileItemReaderBuilder<CustomerCsv>()
        .name("csvReader")
        .resource(resource)
        .linesToSkip(1)
        .delimited()
        .names("id", "firstName", "lastName", "email", "createdDate")
        .targetType(CustomerCsv.class)
        .build();
}
```

### JdbcCursorItemReader (Database - Streaming)

```java
@Bean
@StepScope
public JdbcCursorItemReader<Customer> jdbcCursorReader(
        DataSource dataSource,
        @Value("#{stepExecutionContext['minId']}") Long minId,
        @Value("#{stepExecutionContext['maxId']}") Long maxId) {
    return new JdbcCursorItemReaderBuilder<Customer>()
        .name("customerReader")
        .dataSource(dataSource)
        .sql("SELECT id, first_name, last_name, email, created_date " +
             "FROM customers WHERE id BETWEEN ? AND ? ORDER BY id")
        .preparedStatementSetter(ps -> {
            ps.setLong(1, minId);
            ps.setLong(2, maxId);
        })
        .rowMapper((rs, rowNum) -> new Customer(
            rs.getLong("id"),
            rs.getString("first_name"),
            rs.getString("last_name"),
            rs.getString("email"),
            rs.getTimestamp("created_date").toLocalDateTime()
        ))
        .fetchSize(1000)
        .build();
}
```

### JdbcPagingItemReader (Database - Paged)

```java
@Bean
@StepScope
public JdbcPagingItemReader<Customer> jdbcPagingReader(DataSource dataSource) {
    Map<String, Order> sortKeys = Map.of("id", Order.ASCENDING);

    return new JdbcPagingItemReaderBuilder<Customer>()
        .name("pagingReader")
        .dataSource(dataSource)
        .selectClause("SELECT id, first_name, last_name, email")
        .fromClause("FROM customers")
        .whereClause("WHERE active = true")
        .sortKeys(sortKeys)
        .pageSize(100)
        .rowMapper(new DataClassRowMapper<>(Customer.class))
        .build();
}
```

### JsonItemReader

```java
@Bean
@StepScope
public JsonItemReader<Customer> jsonReader(
        @Value("#{jobParameters['inputFile']}") Resource resource) {
    return new JsonItemReaderBuilder<Customer>()
        .name("jsonReader")
        .resource(resource)
        .jsonObjectReader(new JacksonJsonObjectReader<>(Customer.class))
        .build();
}
```

## ItemProcessor

```java
@Bean
public ItemProcessor<CustomerCsv, Customer> customerProcessor() {
    return csv -> {
        // Return null to filter/skip the item
        if (csv.email() == null || !csv.email().contains("@")) {
            return null;
        }

        return new Customer(
            null,
            csv.firstName().trim(),
            csv.lastName().trim(),
            csv.email().toLowerCase(),
            LocalDateTime.now()
        );
    };
}
```

### Composite Processor (Chaining)

```java
@Bean
public CompositeItemProcessor<CustomerCsv, Customer> compositeProcessor() {
    var composite = new CompositeItemProcessor<CustomerCsv, Customer>();
    composite.setDelegates(List.of(
        validatingProcessor(),
        transformingProcessor()
    ));
    return composite;
}
```

## ItemWriter Implementations

### JdbcBatchItemWriter

```java
@Bean
public JdbcBatchItemWriter<Customer> jdbcWriter(DataSource dataSource) {
    return new JdbcBatchItemWriterBuilder<Customer>()
        .dataSource(dataSource)
        .sql("INSERT INTO customers (first_name, last_name, email, created_date) " +
             "VALUES (:firstName, :lastName, :email, :createdDate)")
        .beanMapped()
        .build();
}
```

### FlatFileItemWriter (CSV Output)

```java
@Bean
@StepScope
public FlatFileItemWriter<Customer> csvWriter(
        @Value("#{jobParameters['outputFile']}") Resource resource) {
    return new FlatFileItemWriterBuilder<Customer>()
        .name("csvWriter")
        .resource(resource)
        .delimited()
        .names("id", "firstName", "lastName", "email")
        .headerCallback(writer -> writer.write("id,firstName,lastName,email"))
        .build();
}
```

## Fault Tolerance (Skip & Retry)

```java
@Bean
public Step faultTolerantStep(JobRepository jobRepository,
                              PlatformTransactionManager transactionManager,
                              ItemReader<Customer> reader,
                              ItemProcessor<Customer, Customer> processor,
                              ItemWriter<Customer> writer) {
    return new StepBuilder("faultTolerantStep", jobRepository)
        .<Customer, Customer>chunk(100)
        .transactionManager(transactionManager)
        .reader(reader)
        .processor(processor)
        .writer(writer)
        .faultTolerant()
        .skip(FlatFileParseException.class)
        .skip(ValidationException.class)
        .skipLimit(50)
        .retry(DeadlockLoserDataAccessException.class)
        .retryLimit(3)
        .listener(new StepExecutionListener() {
            @Override
            public ExitStatus afterStep(StepExecution stepExecution) {
                if (stepExecution.getSkipCount() > 0) {
                    return new ExitStatus("COMPLETED_WITH_SKIPS");
                }
                return stepExecution.getExitStatus();
            }
        })
        .build();
}
```

### Policy-Based Fault Tolerance (Spring Batch 6)

```java
@Bean
public Step policyBasedStep(JobRepository jobRepository,
                            ItemReader<Person> reader,
                            ItemWriter<Person> writer) {
    RetryPolicy retryPolicy = RetryPolicy.builder()
        .maxRetries(10)
        .includes(Set.of(TransientException.class))
        .build();

    SkipPolicy skipPolicy = new LimitCheckingExceptionHierarchySkipPolicy(
        Set.of(FlatFileParseException.class), 50);

    return new ChunkOrientedStepBuilder<Person, Person>("step", jobRepository, 100)
        .reader(reader)
        .writer(writer)
        .faultTolerant()
        .retryPolicy(retryPolicy)
        .skipPolicy(skipPolicy)
        .build();
}
```

## Job Flow Control

### Conditional Flow

```java
@Bean
public Job flowJob(JobRepository jobRepository,
                   Step stepA, Step stepB, Step stepC, Step errorStep) {
    return new JobBuilder("flowJob", jobRepository)
        .start(stepA)
        .on("FAILED").to(errorStep)
        .from(stepA).on("*").to(stepB)
        .from(stepB).on("COMPLETED").to(stepC)
        .end()
        .build();
}
```

### Parallel Steps (Split Flow)

```java
@Bean
public Job parallelJob(JobRepository jobRepository,
                       Step step1, Step step2, Step step3, Step step4) {
    Flow flow1 = new FlowBuilder<SimpleFlow>("flow1")
        .start(step1).next(step2).build();
    Flow flow2 = new FlowBuilder<SimpleFlow>("flow2")
        .start(step3).next(step4).build();

    return new JobBuilder("parallelJob", jobRepository)
        .start(flow1)
        .split(new SimpleAsyncTaskExecutor())
        .add(flow2)
        .end()
        .build();
}
```

## Scaling & Partitioning

### Multi-Threaded Step

```java
@Bean
public Step multiThreadedStep(JobRepository jobRepository,
                              PlatformTransactionManager transactionManager) {
    return new StepBuilder("multiThreadedStep", jobRepository)
        .<String, String>chunk(100)
        .transactionManager(transactionManager)
        .reader(threadSafeReader())
        .processor(processor())
        .writer(writer())
        .taskExecutor(new SimpleAsyncTaskExecutor("batch_"))
        .build();
}
```

> **Important:** The ItemReader must be thread-safe when using multi-threaded steps.

### Partitioned Step

```java
@Bean
public Step partitionedStep(JobRepository jobRepository,
                            Step workerStep,
                            Partitioner partitioner) {
    return new StepBuilder("partitionedStep", jobRepository)
        .partitioner("workerStep", partitioner)
        .step(workerStep)
        .gridSize(10)
        .taskExecutor(new SimpleAsyncTaskExecutor())
        .build();
}

@Bean
public Partitioner rangePartitioner(DataSource dataSource) {
    return gridSize -> {
        Map<String, ExecutionContext> partitions = new HashMap<>();
        // Divide ID range across partitions
        long min = 1, max = 10000;
        long range = (max - min) / gridSize + 1;
        for (int i = 0; i < gridSize; i++) {
            ExecutionContext ctx = new ExecutionContext();
            ctx.putLong("minId", min + (i * range));
            ctx.putLong("maxId", Math.min(min + ((i + 1) * range) - 1, max));
            partitions.put("partition" + i, ctx);
        }
        return partitions;
    };
}
```

## Testing

```java
@SpringBatchTest
@SpringBootTest
class ImportJobTest {

    @Autowired
    private JobLauncherTestUtils jobLauncherTestUtils;

    @Autowired
    private JobRepositoryTestUtils jobRepositoryTestUtils;

    @BeforeEach
    void cleanup() {
        jobRepositoryTestUtils.removeJobExecutions();
    }

    @Test
    void shouldCompleteJob() throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("inputFile", "classpath:test-data.csv")
            .toJobParameters();

        JobExecution execution = jobLauncherTestUtils.launchJob(params);

        assertThat(execution.getStatus()).isEqualTo(BatchStatus.COMPLETED);
        assertThat(execution.getStepExecutions()).hasSize(2);
    }

    @Test
    void shouldCompleteImportStep() throws Exception {
        JobExecution execution = jobLauncherTestUtils.launchStep("importStep");

        assertThat(execution.getStatus()).isEqualTo(BatchStatus.COMPLETED);
        StepExecution step = execution.getStepExecutions().iterator().next();
        assertThat(step.getWriteCount()).isGreaterThan(0);
        assertThat(step.getSkipCount()).isZero();
    }
}
```

## Running Jobs

### Via REST Endpoint

```java
@RestController
@RequestMapping("/api/jobs")
public class JobController {
    private final JobLauncher jobLauncher;
    private final Job importJob;

    public JobController(JobLauncher jobLauncher, Job importJob) {
        this.jobLauncher = jobLauncher;
        this.importJob = importJob;
    }

    @PostMapping("/import")
    public ResponseEntity<String> runImport(@RequestParam String inputFile) throws Exception {
        JobParameters params = new JobParametersBuilder()
            .addString("inputFile", inputFile)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters();

        JobExecution execution = jobLauncher.run(importJob, params);
        return ResponseEntity.accepted().body("Job started: " + execution.getId());
    }
}
```

### Via Command Line

```yaml
# application.yml
spring:
  batch:
    job:
      enabled: false  # Disable auto-run on startup
    jdbc:
      initialize-schema: always
```

```bash
java -jar app.jar --spring.batch.job.name=importJob inputFile=/data/customers.csv
```

## Configuration Properties

```yaml
spring:
  batch:
    job:
      enabled: false              # Don't auto-run jobs on startup
      name: importJob             # Job to run (if enabled)
    jdbc:
      initialize-schema: always   # Create batch metadata tables
      table-prefix: BATCH_        # Table name prefix
      isolation-level-for-create: SERIALIZABLE
```

## Quick Reference

| Component | Purpose |
|-----------|---------|
| `Job` | Batch process definition (one or more steps) |
| `Step` | Independent phase of a job |
| `Chunk` | Read-process-write pattern with commit interval |
| `Tasklet` | Single-operation step (no chunking) |
| `ItemReader` | Reads one item at a time from a source |
| `ItemProcessor` | Transforms/filters items (return null to skip) |
| `ItemWriter` | Writes a chunk of items to a target |
| `JobRepository` | Persists job/step execution metadata |
| `JobLauncher` | Starts job execution |
| `@StepScope` | Late-bind job/step parameters into beans |
| `@EnableBatchProcessing` | Enables Spring Batch infrastructure |
| `@EnableJdbcJobRepository` | Configures JDBC-based job repository |
| `@SpringBatchTest` | Test support with JobLauncherTestUtils |

## Common ItemReader/Writer Implementations

| Reader | Source |
|--------|--------|
| `FlatFileItemReader` | CSV, fixed-width files |
| `JsonItemReader` | JSON files |
| `JdbcCursorItemReader` | Database (streaming cursor) |
| `JdbcPagingItemReader` | Database (paged queries) |
| `JpaPagingItemReader` | JPA entities (paged) |
| `KafkaItemReader` | Kafka topics |

| Writer | Target |
|--------|--------|
| `FlatFileItemWriter` | CSV, fixed-width files |
| `JsonFileItemWriter` | JSON files |
| `JdbcBatchItemWriter` | Database (JDBC batch insert) |
| `JpaItemWriter` | JPA entities |
| `KafkaItemWriter` | Kafka topics |
