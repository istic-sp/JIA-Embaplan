# Referência de Diagramas Mermaid por Stack

> ⚠️ **Nunca use ASCII art** (`┌─┐ │ └┘ → ▼`) em documentação Markdown.
> Sempre converta para blocos Mermaid. Exemplos abaixo.

---

## Monorepo Fullstack — Next.js + ASP.NET Core (Clean Architecture)

```mermaid
C4Container
  title Containers — Monorepo [Nome do Projeto]

  Person(user, "Usuário", "Acessa pelo browser")

  Container_Boundary(repo, "Monorepo") {
    Container(fe, "Frontend", "Next.js 15 + TypeScript\nTailwindCSS + React Query", "Interface web com SSR/RSC")
    Container(be, "Backend API", "ASP.NET Core 8\nClean Architecture + CQRS", "API REST com MediatR + FluentValidation")
    ContainerDb(db, "Banco de Dados", "PostgreSQL + EF Core", "Persistência principal")
    Container(cache, "Cache", "Redis", "Sessions e dados frequentes")
    Container(storage, "Storage", "Azure Blob Storage", "Arquivos e mídias")
    Container(queue, "Mensageria", "RabbitMQ / MQTT", "Eventos assíncronos")
  }

  System_Ext(telemetry, "Observabilidade", "OpenTelemetry + Jaeger\nPrometheus")

  Rel(user, fe, "Acessa", "HTTPS")
  Rel(fe, be, "Chama", "REST/JSON")
  Rel(be, db, "Lê/Escreve", "EF Core")
  Rel(be, cache, "Cache", "StackExchange.Redis")
  Rel(be, storage, "Upload/Download", "Azure SDK")
  Rel(be, queue, "Publica/Consome", "AMQP")
  Rel(be, telemetry, "Métricas e traces", "OTLP")
```

```mermaid
graph TD
  subgraph "Frontend — Next.js"
    PAGES[Pages / App Router\nSSR + RSC]
    COMP[Components\nReact + Tailwind]
    HOOKS[Hooks / React Query\nEstado e cache]
    APIFE[API Routes\nProxy / BFF]
  end

  subgraph "Backend — ASP.NET Core"
    CTRL[Controllers\nEndpoints REST]
    MED[MediatR\nCommands + Queries]
    VAL[FluentValidation\nValidações]
    subgraph "Clean Architecture"
      APP[Application\nUse Cases]
      DOM[Domain\nEntidades + Regras]
      INF[Infrastructure\nRepositórios + Serviços]
    end
  end

  subgraph "Dados"
    PG[(PostgreSQL\nEF Core)]
    RD[(Redis\nCache)]
    BL[(Azure Blob\nStorage)]
  end

  PAGES --> COMP
  PAGES --> HOOKS
  HOOKS --> APIFE
  APIFE --> CTRL
  CTRL --> MED
  MED --> VAL
  MED --> APP
  APP --> DOM
  APP --> INF
  INF --> PG
  INF --> RD
  INF --> BL
```

---

Use este arquivo como referência ao gerar diagramas no ARCHITECTURE.md.
Copie o exemplo mais próximo do projeto e adapte com os nomes reais.

---

## Next.js / React Fullstack

```mermaid
C4Container
  title Containers — Aplicação Next.js

  Person(user, "Usuário", "Acessa pelo browser")

  Container_Boundary(app, "Next.js App") {
    Container(pages, "Pages / App Router", "Next.js", "Renderização SSR/SSG e rotas de página")
    Container(api, "API Routes", "Next.js API", "Endpoints REST internos")
    Container(components, "Components", "React", "UI reutilizável")
  }

  ContainerDb(db, "Banco de Dados", "PostgreSQL / MongoDB", "Persistência principal")
  System_Ext(auth, "Auth Provider", "NextAuth / Clerk / Auth0")
  System_Ext(storage, "Object Storage", "S3 / Cloudflare R2")

  Rel(user, pages, "Acessa", "HTTPS")
  Rel(pages, api, "Chama", "fetch / axios")
  Rel(pages, components, "Renderiza")
  Rel(api, db, "Query", "Prisma / Mongoose")
  Rel(api, auth, "Valida sessão", "OAuth / JWT")
  Rel(api, storage, "Upload/Download", "SDK")
```

---

## FastAPI / Python Backend

```mermaid
graph LR
  subgraph "API Layer"
    R[Router / Endpoints]
    M[Middlewares\nAuth · CORS · Logging]
  end
  subgraph "Application Layer"
    S[Services / Use Cases]
    SC[Schemas\nPydantic]
  end
  subgraph "Domain Layer"
    DO[Domain Models]
    DI[Interfaces\nRepositórios]
  end
  subgraph "Infrastructure Layer"
    DB[(PostgreSQL\nSQLAlchemy)]
    CA[(Redis\nCache)]
    EX[External APIs]
  end

  R --> M --> S
  S --> SC
  S --> DO
  DO --> DI
  DI --> DB
  DI --> CA
  S --> EX
```

---

## Node.js / Express REST API

```mermaid
sequenceDiagram
  actor C as Cliente
  participant MW as Middleware\n(Auth/Validation)
  participant CT as Controller
  participant SV as Service
  participant RP as Repository
  participant DB as Database

  C->>MW: POST /api/recurso
  MW->>MW: Valida JWT
  MW->>CT: req autorizado
  CT->>CT: Valida body (Zod/Joi)
  CT->>SV: service.create(dto)
  SV->>SV: Regras de negócio
  SV->>RP: repository.save(entity)
  RP->>DB: INSERT ...
  DB-->>RP: id gerado
  RP-->>SV: entity salva
  SV-->>CT: resultado
  CT-->>C: 201 Created { data }
```

---

## Spring Boot (Java / Kotlin)

```mermaid
graph TD
  subgraph "Presentation"
    REST[REST Controllers\n@RestController]
    DTO[DTOs\nRequest/Response]
  end
  subgraph "Business"
    SVC[Services\n@Service]
    MAPPER[Mappers\nMapStruct]
  end
  subgraph "Data"
    REPO[Repositories\n@Repository / JPA]
    ENTITY[Entities\n@Entity]
  end
  subgraph "Cross-Cutting"
    SEC[Security\nSpring Security + JWT]
    CACHE[Cache\n@Cacheable + Redis]
    EXC[Exception Handler\n@ControllerAdvice]
  end

  REST --> DTO
  REST --> SVC
  SVC --> MAPPER
  SVC --> REPO
  REPO --> ENTITY
  SEC -.-> REST
  CACHE -.-> SVC
  EXC -.-> REST
```

---

## Microsserviços

```mermaid
C4Container
  title Arquitetura de Microsserviços

  Person(user, "Usuário")

  Container_Boundary(gateway, "API Gateway") {
    Container(gw, "Gateway", "Kong / Nginx / custom", "Roteamento, auth, rate limit")
  }

  Container_Boundary(services, "Serviços") {
    Container(svc_a, "Serviço A", "[tech]", "[responsabilidade]")
    Container(svc_b, "Serviço B", "[tech]", "[responsabilidade]")
    Container(svc_c, "Serviço C", "[tech]", "[responsabilidade]")
  }

  Container_Boundary(infra, "Infraestrutura") {
    ContainerDb(db_a, "DB Serviço A", "PostgreSQL")
    ContainerDb(db_b, "DB Serviço B", "MongoDB")
    Container(bus, "Message Bus", "RabbitMQ / Kafka", "Eventos assíncronos")
  }

  Rel(user, gw, "HTTPS")
  Rel(gw, svc_a, "REST")
  Rel(gw, svc_b, "REST")
  Rel(svc_a, db_a, "query")
  Rel(svc_b, db_b, "query")
  Rel(svc_a, bus, "publica evento")
  Rel(svc_c, bus, "consome evento")
```

---

## Diagrama ER (Banco Relacional)

```mermaid
erDiagram
  USER {
    uuid id PK
    string email
    string name
    timestamp created_at
  }
  ORGANIZATION {
    uuid id PK
    string name
    string slug
  }
  PROJECT {
    uuid id PK
    string title
    string status
    uuid org_id FK
    uuid owner_id FK
    timestamp created_at
  }
  MEMBER {
    uuid user_id FK
    uuid org_id FK
    string role
  }

  USER ||--o{ MEMBER : "pertence a"
  ORGANIZATION ||--o{ MEMBER : "tem"
  ORGANIZATION ||--o{ PROJECT : "possui"
  USER ||--o{ PROJECT : "é dono de"
```

---

## Fluxo de Autenticação JWT

```mermaid
sequenceDiagram
  actor U as Usuário
  participant FE as Frontend
  participant AUTH as Auth Endpoint
  participant MW as JWT Middleware
  participant API as API Protegida
  participant DB as Database

  U->>FE: Login (email + senha)
  FE->>AUTH: POST /auth/login
  AUTH->>DB: Busca usuário
  DB-->>AUTH: User record
  AUTH->>AUTH: Verifica hash da senha
  AUTH-->>FE: { access_token, refresh_token }
  FE->>FE: Armazena tokens

  U->>FE: Ação autenticada
  FE->>MW: GET /api/recurso\nAuthorization: Bearer <token>
  MW->>MW: Verifica assinatura JWT
  MW->>MW: Extrai claims (userId, role)
  MW->>API: req com userId injetado
  API->>DB: Query com filtro de userId
  DB-->>API: Dados
  API-->>FE: Resposta
```

---

## Worker / Job Assíncrono

```mermaid
flowchart LR
  TR[Trigger\nCron / Evento / Webhook] --> Q[(Fila\nRedis/RabbitMQ/SQS)]
  Q --> W{Worker\nProcessamento}
  W -->|Sucesso| OK[(Resultado\nDB/Storage)]
  W -->|Falha| RT[Retry com\nbackoff exponencial]
  RT --> Q
  RT -->|Max retries| DLQ[(Dead Letter Queue)]
  DLQ --> AL[Alerta\nMonitoramento]
```