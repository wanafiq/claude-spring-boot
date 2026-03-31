### 1. Plan Mode Default
- Enter plan mode for ANY not-trivial task (3+ steps or architectural decisions)
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until the mistake rate drops
- Review lessons at session start for a project

### 3. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 4. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes. Don't overengineer
- Challenge your own work before presenting it

### 5. Code Quality
- After finishing each task / module: run `mvn spotless:check` then `mvn spotless:apply` to fix violations
- Follow Palantir Java Format — no manual formatting overrides or `@SuppressWarnings` for style
- Run `mvn compile` after formatting to catch any issues introduced by auto-format
- Code must be self-documenting: meaningful names, small methods, single-responsibility classes
- No Javadoc or comments unless the logic is genuinely non-obvious. Never state the obvious
- No dead code, unused imports, or commented-out blocks in committed code

### 6. Session Start Awareness
- At the start of each session: review available skills, agents, and tools
- Check `tasks/lessons.md` for past mistakes and patterns to avoid
- Understand what capabilities are available before jumping into work
- Use the right skill or agent for the job — don't reinvent what already exists

### 7. Java Naming Conventions
- **Packages**: all lowercase, reverse domain notation, underscores for multi-word segments (`com.rh.mydebit`, `com.rh.user_service`)
- **Classes / Interfaces**: PascalCase, nouns for classes, adjectives or nouns for interfaces (`EmployeeService`, `Serializable`)
- **Methods**: camelCase, start with a verb (`findById`, `calculateSalary`, `isActive`)
- **Variables / Fields**: camelCase, descriptive nouns (`employeeName`, `totalCount`)
- **Constants** (`static final`): UPPER_SNAKE_CASE (`MAX_RETRY_COUNT`, `DEFAULT_PAGE_SIZE`)
- **Enums**: PascalCase for type, UPPER_SNAKE_CASE for values (`OrderStatus.PENDING`)
- **Type Parameters**: single uppercase letter (`T`, `E`, `K`, `V`)
- **Test Classes**: mirror source class name with `Test` suffix (`EmployeeServiceTest`)

### 8. Git Commit Convention
  ```
  <type>[optional scope]: <description>

  [optional body]

  [optional footer(s)]
  ```
- **Allowed types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- **Scope**: optional, in parentheses — identifies the affected module (`feat(auth):`, `fix(api):`)
- **Description**: imperative mood, lowercase, no period at end (`add user endpoint` not `Added user endpoint.`)
- **Body**: optional, explain the "why" not the "what" — separated by a blank line from the description
- **Breaking changes**: append `!` after type/scope (`feat!:`) or add `BREAKING CHANGE:` footer
- **Footer**: use `token: value` format (`Reviewed-by:`, `Refs:`, `Closes #123`)
- Keep the subject line under 72 characters

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards

## Project General Instructions

- Always use the latest versions of dependencies.
- Always write Java code as the Spring Boot application.
- Always use Maven for dependency management.
- Always create test cases for the generated code both positive and negative.
- Minimize the amount of code generated.
- The Maven artifact name must be the same as the parent directory name.
- Use semantic versioning for the Maven project. Each time you generate a new version, bump the PATCH section of the version number.
- Do not use the Lombok library.
- Update README.md each time you generate a new version.
