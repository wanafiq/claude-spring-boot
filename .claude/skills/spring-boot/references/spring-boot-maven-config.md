# Maven Configuration for Spring Boot Project

This guide provides instructions on how to configure a Maven project for a Spring Boot application.

## Key principles

Follow these principles when using the Maven build tool for a Spring Boot application:

- Configure `spotless-maven-plugin` to automatically format the code and verify whether code is formatted correctly or not.
- Configure `jacoco-maven-plugin` to ensure tests are written meeting the desired code coverage level.

## pom.xml configuration

```xml
<properties>
    <spotless.version>{latestversion}</spotless.version>
    <palantir-java-format.version>{latestversion}</palantir-java-format.version>
    <jacoco-maven-plugin.version>{latestversion}</jacoco-maven-plugin.version>
    <jacoco.minimum.coverage>0.80</jacoco.minimum.coverage>
</properties>

<build>
    <plugins>
        <plugin>
            <groupId>org.jacoco</groupId>
            <artifactId>jacoco-maven-plugin</artifactId>
            <version>${jacoco-maven-plugin.version}</version>
            <executions>
                <!-- Attach JaCoCo agent -->
                <execution>
                    <goals>
                        <goal>prepare-agent</goal>
                    </goals>
                </execution>
                <!-- Generate report -->
                <execution>
                    <id>report</id>
                    <phase>verify</phase>
                    <goals>
                        <goal>report</goal>
                    </goals>
                </execution>
                <!-- Enforce coverage rule -->
                <execution>
                    <id>check</id>
                    <phase>verify</phase>
                    <goals>
                        <goal>check</goal>
                    </goals>
                    <configuration>
                        <rules>
                            <rule>
                                <element>BUNDLE</element>
                                <limits>
                                    <limit>
                                        <counter>LINE</counter>
                                        <value>COVEREDRATIO</value>
                                        <minimum>${jacoco.minimum.coverage}</minimum>
                                    </limit>
                                </limits>
                            </rule>
                        </rules>
                    </configuration>
                </execution>
            </executions>
        </plugin>
        <plugin>
            <groupId>com.diffplug.spotless</groupId>
            <artifactId>spotless-maven-plugin</artifactId>
            <version>${spotless.version}</version>
            <configuration>
                <java>
                    <importOrder/>
                    <removeUnusedImports/>
                    <formatAnnotations/>
                    <palantirJavaFormat>
                        <version>${palantir-java-format.version}</version>
                    </palantirJavaFormat>
                </java>
            </configuration>
            <executions>
                <execution>
                    <goals>
                        <goal>check</goal>
                    </goals>
                    <phase>compile</phase>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```