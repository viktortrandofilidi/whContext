# Per-repo commands, formatters & validation gates

The code lives in sub-repos under the workspace root — `match`, `hamster`,
`orchestrator`, `commons-kotlin`. The project dir may be the workspace root (code in
`./match`, `./hamster`, …) or one of the repos itself. **Detect the repo you changed,
then run that repo's commands from inside it** — every command below assumes you are
`cd`'d into the sub-repo.

```bash
# Which repo has uncommitted changes?
for d in match hamster orchestrator commons-kotlin .; do
  git -C "$d" status --porcelain 2>/dev/null | grep -q . && echo "changed: $d"
done
```

## match (Maven — Java 11/Kotlin 2.1 + React)

**Formatter — mandatory before finishing (CI fails otherwise):**
```bash
mvn spotless:apply          # Java (uses Prettier for Java, config .prettierrc.yaml)
mvn spotless:check          # verify only (what the reviewer runs)
```

**Frontend (`portal-admin/frontend`) — whole-tree gates, same as CI:**
```bash
pnpm ci:format              # prettier check
pnpm ci:lint                # eslint, --max-warnings 0
pnpm checkts                # tsc
pnpm prettier --write <files>   # format ONLY the files you touched, before commit
```
- Format the files you touched with `pnpm prettier --write`, not the whole tree — a
  global pass belongs in its own PR.
- A whole-tree `pnpm ci:lint` failure surfaces as a red **build-jars / build-docker**
  check, not an obvious frontend one — run the whole-tree gate before you push.
- `contextual-analytics` frontend is at `contextual-analytics/src/main/resources/app`.

**Tests:**
```bash
mvn test                                   # unit
mvn test -Dtest=ClassName#methodName       # single
mvn test-compile failsafe:integration-test failsafe:verify -Pfailsafe   # integration (*IT.java)
```

## hamster (Gradle — Kotlin, Spring Boot 3.4)

**Formatter — mandatory; a pre-push hook rejects unformatted code:**
```bash
./gradlew spotlessApply     # run before finishing; this is the expected formatting gate
./gradlew spotlessCheck     # verify only
```
- Gradle config needs a **JDK 21 launcher** — set `JAVA_HOME` to a 21 JDK (e.g.
  `microsoft-21`) or the build fails on Java 11.
- **Do NOT run heavy Gradle tasks unsolicited** — `:server:build`, full `test`, and
  `deployDataflowFlexTemplate` are slow (clean build can take ~40 min). Run them only
  when the user explicitly asks. `spotlessApply` is the one expected gate; keep the
  rest opt-in.

**Tests (only when asked):**
```bash
./gradlew test
./gradlew :hamster-core:test --tests "ClassificationServiceTest"
```

**compass CLI** is the supported way to talk to a running hamster server — prefer it
over hand-crafted `curl`. `--help` at any level discovers commands/args/enums.

## orchestrator (Gradle — Kotlin/Java 17)

```bash
./gradlew spotlessApply     # mandatory before finishing
./gradlew build -x test     # build (opt-in)
./gradlew test --tests "com.windfall.orchestrator.CentralOrchestratorTest"
```
Proto changes (`orchestrator-proto/`) follow a two-PR flow — see `orchestrator/CLAUDE.md`.

## commons-kotlin (Gradle — library, Java 11 / Kotlin 2.1)

```bash
./gradlew spotlessApply     # mandatory before finishing
./gradlew build
./gradlew :event-types:test
```
Contract changes are **additive only** (nullable fields with defaults); version bump
is driven by the commit message (`+semver: feature|fix|breaking`).

## Cross-cutting cleanup (before push)

- If the task used an ephemeral env, strip peer-image override blocks from
  `deploy/environments/ephemeral/*.values.yaml` and restore them to master state.
- Never commit or push without an explicit request from the user.
