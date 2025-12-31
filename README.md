# LuaAIDiary

A Lua-based WordPress-like blog system

## Overview

LuaAIDiary is a high-performance blog system built with OpenResty (Nginx + LuaJIT), Lapis, PostgreSQL, and Redis. It provides an easy setup using Docker Compose and a development environment that allows testing during development.

## Key Features

- **Ultra-Fast Performance**: Asynchronous I/O processing with OpenResty + LuaJIT delivers several times better performance than traditional PHP-based CMS
- **AI Content Generation**: Automatically generate complete articles from topics using Gemini API integration
- **AI Proofreading**: Automatically improve grammar, expression, and structure
- **Complete Admin Panel**: Intuitive content management with WordPress-style dashboard
- **Lightweight**: Fast script execution with LuaJIT
- **Role-Based Access Control**: 5-tier permission management (admin/editor/author/contributor/subscriber)
- **Full-Text Search**: High-speed search with PostgreSQL GIN indexes
- **Test Environment**: Automated testing support with Busted
- **Developer Tools**: Enhanced development efficiency with Makefile and Luacheck
- **Scalable**: Horizontal scaling with Redis and PostgreSQL
- **Hot Reload**: Automatic reflection of code changes
- **Secure**: bcrypt, CSRF protection, encrypted API key management

## ⚡ Performance

LuaAIDiary is designed as a high-performance CMS, achieving the following benchmark results:

- **Throughput**: 70,405 req/sec
- **Latency**: 2.83ms average
- **Scale**: Capable of handling 6 billion PV/day, 1.8 trillion PV/month
- **Rating**: ⭐⭐⭐⭐⭐ Enterprise Grade

*Benchmark Environment: AMD Ryzen 7 6800HS (8C/16T), 7.8GB RAM, Ubuntu 24.04 LTS (WSL2)*

📊 **Detailed Performance Report**: [`tests/performance/results/performance_improvement_report.md`](tests/performance/results/performance_improvement_report.md)

## Tech Stack

- **Web Framework**: Lapis (OpenResty/Nginx + LuaJIT)
- **Database**: PostgreSQL 15 (full-text search, JSONB support)
- **Cache/Session**: Redis 7
- **AI Integration**: Google Gemini API
- **Test Framework**: Busted
- **Static Analysis**: Luacheck
- **Containerization**: Docker & Docker Compose
- **Language**: Lua

### Why OpenResty + LuaJIT?

OpenResty is a platform that integrates LuaJIT into Nginx, offering the following advantages:

1. **Asynchronous I/O**: Event-driven architecture provides high performance even in high-concurrency environments
2. **Low Memory Usage**: LuaJIT's JIT compiler is more memory-efficient than PHP and similar languages
3. **Fast Response**: Lua code runs directly on Nginx's event loop, eliminating CGI/FastCGI overhead
4. **C Extension Compatibility**: FFI (Foreign Function Interface) allows direct calls to C libraries

## Directory Structure

```
LuaAIDiary/
├── app/                        # Application code
│   ├── init.lua               # Lapis application entry point
│   ├── config/                # Configuration files
│   ├── controllers/           # Controller layer
│   ├── models/                # Model layer
│   ├── views/                 # View layer (templates)
│   ├── middleware/            # Middleware
│   ├── theme_engine/          # Theme engine (WordPress compatibility)
│   └── utils/                 # Utility functions
├── tests/                     # Test code
│   ├── test_helper.lua        # Test helper
│   ├── test_database.lua      # Database tests
│   └── test_health.lua        # Health check tests
├── static/                    # Static files
│   ├── css/
│   ├── js/
│   └── images/
├── wp-content/                # WordPress-compatible content
│   └── themes/                # Themes directory
│       └── luaaidiary-default/  # Default theme
├── docker/                    # Docker-related files
│   └── web/
│       ├── Dockerfile         # OpenResty + Lapis environment
│       └── nginx.conf         # Nginx configuration
├── postgresql/                # PostgreSQL-related
│   └── init/
│       └── 01_create_tables.sql  # Database initialization script
├── Makefile                   # Development task automation
├── .luacheckrc               # Luacheck configuration
├── docker-compose.yml         # Docker Compose configuration
├── .env.example              # Environment variable sample
├── LICENSE                   # MIT License
├── ARCHITECTURE.md           # Architecture design document
└── DESIGN.md                 # Detailed design document
```

## Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- Make (optional, recommended)

### Initial Setup (Recommended)

Automated setup using Makefile:

```bash
# Clone the repository
git clone https://github.com/hawkie275/LuaAIDiary.git
cd LuaAIDiary

# Initial setup (.env creation, build, startup)
make setup
```

This automatically executes:
1. `.env` file creation
2. Docker image build
3. Service startup
4. Database initialization

### Manual Setup

If not using Makefile:

```bash
# 1. Create .env file
cp .env.example .env

# 2. Build Docker images and start services
docker compose up -d --build

# 3. Wait for database startup (about 10 seconds)
sleep 10
```

### Verification

Access the following URL in your browser:

```
http://localhost:8080
```

Health check:
```bash
curl http://localhost:8080/health
# or
make health
```

## Development Commands (Makefile)

The project includes a convenient Makefile:

```bash
# Display help
make help

# Start development server (foreground)
make dev

# Start services (background)
make up

# Stop services
make down

# Restart services
make restart

# Display logs
make logs          # All services
make logs-web      # Web server only
make logs-db       # Database only
make logs-redis    # Redis only

# Connect to shell
make shell         # Web container
make shell-db      # DB container
make psql          # PostgreSQL client
make redis-cli     # Redis client

# Run tests
make test          # All tests

# Reset database
make db-reset

# Static analysis
make lint

# Health check
make health

# Check service status
make status

# Cleanup (delete data)
make clean
```

## Admin Panel

### Access Method

Access the admin panel at:

```
http://localhost:8080/admin
```

or

```
http://localhost:8080/admin/dashboard
```

### Default Login Credentials

After initial setup, log in with the administrator account:

- **Username**: `admin`
- **Password**: Password set in the database initialization script
  - Default can be checked in `postgresql/init/02_update_admin_password.sql`
  - **For security, change the password immediately after first login**

### Changing Password

1. Log in to the admin panel
2. Select "Change Password" from the user menu in the upper right
3. Enter current password and new password

Or access directly:

```
http://localhost:8080/admin/change-password
```

### Main Admin Features

#### Dashboard (`/admin/dashboard`)
- Site statistics display
  - Post count (all statuses)
  - Category count
  - Tag count
  - Comment count
- Recent 5 posts
- System information (Lua version, server time, DB connection status)

#### Post Management (`/admin/posts`)
- Post list display
- Create new post
- Edit post
- Delete post
- Status management (draft/published/trash)
- Markdown preview
- Category and tag assignment

#### Category Management (`/admin/categories`)
- Category list
- Create, edit, delete categories
- Hierarchical structure management

#### Tag Management (`/admin/tags`)
- Tag list
- Create, edit, delete tags

#### User Management (`/admin/users`)
- User list
- Create new user
- Edit user information
- Change roles (admin/editor/author/contributor/subscriber)
- Delete user

#### Site Settings (`/admin/settings`)
- Site basic information
- AI settings (Gemini API)
- Theme settings

#### Profile Management (`/admin/profile`)
- View and edit your own profile
- Change password

## Gemini AI Features

LuaAIDiary integrates with Google Gemini API to provide AI-powered article writing assistance.

### Main Features

#### 1. AI Article Generation

Automatically generate complete articles from topics and keywords.

**Features**:
- Auto-generate titles and content
- Suggest heading structure
- SEO-conscious writing
- Customizable word count and tone

**Usage**:
1. Click "AI Generate" button on post edit screen
2. Enter topic and keywords
3. Optionally specify target audience, word count, and tone
4. Review and edit the generated article

**API Endpoint**:
```bash
POST /api/gemini/generate-article
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "topic": "LuaJIT Performance",
  "keywords": "Lua, JIT, Performance",
  "target_audience": "Developers",
  "word_count": 2000,
  "tone": "technical"
}
```

#### 2. AI Proofreading

Analyze existing articles and provide suggestions for improving grammar, expression, and structure.

**Features**:
- Grammar check
- Expression improvement suggestions
- Readability enhancement
- Tone adjustment

**Usage**:
1. Enter content in post edit screen
2. Click "AI Proofread" button
3. Review improvement suggestions
4. Apply necessary corrections

**API Endpoint**:
```bash
POST /api/gemini/proofread
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "content": "Article content to proofread...",
  "tone": "formal"
}
```

### Setting Up Gemini API Key

To use AI features, each user must set up their individual Gemini API key.

#### 1. Obtaining an API Key

1. Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Log in with your Google account
3. Click "Create API Key"
4. Copy the generated API key

#### 2. Configuring the API Key

From admin panel:

1. Access `/admin/settings`
2. Select "AI Settings" tab
3. Enter Gemini API key
4. Click "Save"

Via API:

```bash
POST /api/settings/gemini-api-key
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN

{
  "api_key": "YOUR_GEMINI_API_KEY"
}
```

#### 3. Security

- API keys are encrypted with AES-256-CBC before storing in database
- Each user manages their individual API key
- Master encryption key managed via environment variable (`ENCRYPTION_KEY`)
- Only the owner can view and update their API key

### Customizing AI Settings

You can adjust the quality and style of generated articles by customizing prompt templates.

**Configuration Options**:
- **Model Selection**: `gemini-2.5-flash`, `gemini-1.5-pro`, etc.
- **Article Generation Prompt**: Prompt template for article generation
- **Proofreading Prompt**: Prompt template for proofreading
- **Default Target Audience**: Target audience for articles
- **Default Tone**: formal, casual, technical, etc.

### API Connection Test

Test if your API key is configured correctly:

```bash
POST /api/gemini/test-connection
Content-Type: application/json
X-CSRF-Token: YOUR_CSRF_TOKEN
```

Success response:
```json
{
  "success": true,
  "data": {
    "success": true,
    "message": "API connection successful",
    "response": "Connection successful"
  }
}
```

## Available Endpoints

### Public Endpoints

| Endpoint | Description | Response |
|----------|-------------|----------|
| `GET /` | Homepage (post list) | HTML |
| `GET /:slug` | Single post | HTML |
| `GET /category/:slug` | Category archive | HTML |
| `GET /tag/:slug` | Tag archive | HTML |
| `GET /author/:username` | Author archive | HTML |
| `GET /search` | Search results | HTML |
| `GET /health` | Health check | JSON |
| `GET /api/db-test` | PostgreSQL connection test | JSON |
| `GET /api/redis-test` | Redis connection test | JSON |

### Authentication API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/auth/register` | POST | User registration | No |
| `/api/auth/login` | POST | Login | No |
| `/api/auth/logout` | POST | Logout | Yes |
| `/api/auth/me` | GET | Get current user info | Yes |
| `/api/auth/change-password` | POST | Change password | Yes |
| `/api/auth/check` | GET | Check auth status | Optional |

### Post API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/posts` | GET | Get post list | Optional |
| `/api/posts` | POST | Create post | Yes (author+) |
| `/api/posts/:id` | GET | Get post details | Optional |
| `/api/posts/:id` | PUT | Update post | Yes (owner) |
| `/api/posts/:id` | DELETE | Delete post | Yes (owner) |

### Category API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/categories` | GET | Get category list | No |
| `/api/categories` | POST | Create category | Yes (editor+) |
| `/api/categories/:id` | GET | Get category details | No |
| `/api/categories/:id` | PUT | Update category | Yes (editor+) |
| `/api/categories/:id` | DELETE | Delete category | Yes (editor+) |

### Tag API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/tags` | GET | Get tag list | No |
| `/api/tags` | POST | Create tag | Yes (author+) |
| `/api/tags/:id` | GET | Get tag details | No |
| `/api/tags/:id` | PUT | Update tag | Yes (editor+) |
| `/api/tags/:id` | DELETE | Delete tag | Yes (editor+) |

### Admin Panel Endpoints

| Endpoint | Description | Permission |
|----------|-------------|------------|
| `GET /admin` | Admin top (redirect to dashboard) | editor+ |
| `GET /admin/dashboard` | Dashboard | editor+ |
| `GET /admin/posts` | Post list | editor+ |
| `GET /admin/posts/new` | New post form | author+ |
| `GET /admin/posts/:id/edit` | Edit post form | owner |
| `GET /admin/categories` | Category management | editor+ |
| `GET /admin/tags` | Tag management | editor+ |
| `GET /admin/users` | User management | admin |
| `GET /admin/settings` | Site settings | admin |
| `GET /admin/profile` | Profile display | all users |
| `GET /admin/login` | Login form | none |
| `GET /admin/change-password` | Password change form | required |

### Gemini AI API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/gemini/generate-article` | POST | AI article generation | Yes |
| `/api/gemini/proofread` | POST | AI proofreading | Yes |
| `/api/gemini/test-connection` | POST | API connection test | Yes |

### AI Settings API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/settings/ai-preferences` | GET | Get AI settings | Yes |
| `/api/settings/ai-preferences` | PUT | Update AI settings | Yes |
| `/api/settings/gemini-api-key` | POST | Save API key | Yes |
| `/api/settings/gemini-api-key` | DELETE | Delete API key | Yes |

### Other Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/csrf-token` | GET | Get CSRF token |
| `/api/preview/markdown` | POST | Markdown preview |

### Example: Health Check

```bash
curl http://localhost:8080/health
```

Response example:
```json
{
  "status": "ok",
  "service": "LuaAIDiary",
  "timestamp": 1703500000,
  "version": "0.1.0"
}
```

### Example: Database Connection Test

```bash
curl http://localhost:8080/api/db-test
```

Response example:
```json
{
  "status": "success",
  "message": "Database connection successful",
  "postgres_version": "PostgreSQL 15.x",
  "host": "db",
  "database": "luaaidiary"
}
```

## Running Tests

### Run all tests

```bash
make test
```

or

```bash
docker compose exec web busted tests/
```

### Run specific test files

```bash
make test-file FILE=tests/test_database.lua
```

### Test Contents

- **test_database.lua**: Database connection and schema tests
- **test_health.lua**: Health check endpoint tests

## Database Schema

The following tables are automatically created:

- **users** - User information (authentication, permission management)
- **posts** - Posts (article content, status)
- **comments** - Comments (thread support)
- **categories** - Categories (hierarchical structure support)
- **tags** - Tags
- **post_categories** - Many-to-many relationship between posts and categories
- **post_tags** - Many-to-many relationship between posts and tags
- **user_settings** - User settings (Gemini API key, etc.)
- **post_meta** - Post metadata (custom fields)

For detailed schema definitions, refer to [`postgresql/init/01_create_tables.sql`](postgresql/init/01_create_tables.sql).

## Development Workflow

### Hot Reload

Files in the `app/` directory are mounted between the host machine and container, so changes are immediately reflected upon editing.

### Code Static Analysis

```bash
make lint
```

Uses Luacheck to check code quality. Configuration is managed in `.luacheckrc`.

### Database Reset

Reset the database to a clean state during development:

```bash
make db-reset
```

### Log Monitoring

Monitoring logs during development is convenient:

```bash
make logs-web
```

## Security

### Important Settings for Production

**⚠️ You must change the following settings in production:**

1. **Change Database Password**
   ```bash
   # Change to strong password in .env file
   POSTGRES_PASSWORD=strong_random_password
   ```

2. **Generate Encryption Key**
   ```bash
   # Generate a secure 32-byte key
   openssl rand -hex 32
   
   # Set in .env file
   ENCRYPTION_KEY=generated_key
   ```

3. **Change Admin Password**
   - Change immediately after first login
   - Can be changed from `/admin/change-password`

4. **Environment Variable Management**
   - **Never commit `.env` file to Git**
   - Verify `.env` is included in `.gitignore`
   - Manage environment variables securely in production (AWS Secrets Manager, Hashicorp Vault, etc.)

5. **Use HTTPS**
   - Always configure HTTPS/TLS in production
   - Free SSL certificates available through Let's Encrypt

### Implemented Security Features

#### Password Security
- **bcrypt**: 12 rounds of hashing
- **Salt**: Auto-generated
- **Minimum length**: 8 characters

#### Session Management
- **Storage**: Redis (in-memory)
- **Expiration**: 7 days
- **Cookie settings**:
  - `HttpOnly`: Not accessible from JavaScript
  - `SameSite=Lax`: Mitigates CSRF attacks
  - `Secure`: HTTPS only in production (requires configuration)

#### CSRF Protection
- CSRF token verification for all mutation operations
- Tokens are 32-byte random strings
- Generated per session

#### API Key Encryption
- **Encryption method**: AES-256-CBC
- **Master key**: Managed via environment variable
- **Access control**: Only owner can view

#### Role-Based Access Control (RBAC)
- **admin**: All operations allowed
- **editor**: Content management and publishing
- **author**: Manage own articles
- **contributor**: Create article drafts
- **subscriber**: View only

#### Input Validation
- All input data validated server-side
- SQL injection protection (parameterized queries)
- XSS protection (output escaping)

## Environment Variables

Environment variables configurable in `.env` file:

```bash
# PostgreSQL settings
POSTGRES_PASSWORD=change_this_secure_password
POSTGRES_DB=luaaidiary
POSTGRES_USER=luaaidiary

# Redis settings
REDIS_HOST=redis
REDIS_PORT=6379

# Lapis settings
LAPIS_ENVIRONMENT=development

# Encryption settings (must change!)
ENCRYPTION_KEY=change_this_to_a_secure_32_byte_key_in_production

# Gemini API settings (optional)
GEMINI_API_KEY=your_gemini_api_key_here
```

For details, refer to [`.env.example`](.env.example).

## Troubleshooting

### Services Won't Start

```bash
# Check service status
make status

# Check logs
make logs

# Complete cleanup and re-setup
make clean
make setup
```

### Ports Already in Use

If ports 8080, 5432, or 6379 are already in use, change the port settings in `docker-compose.yml`.

### Database Connection Error

```bash
# Check database container status
docker compose ps db

# Check database logs
make logs-db

# Reset database
make db-reset
```

### Tests Fail

```bash
# Verify services started normally
make health

# Database connection test
curl http://localhost:8080/api/db-test

# Redis connection test
curl http://localhost:8080/api/redis-test
```

### Container Build Error

```bash
# Rebuild without cache
make build
```

## Project Structure Details

### `/app` - Application Code

- **init.lua**: Main entry point of Lapis application
- **config/**: Configuration such as database connections
- **controllers/**: Request handlers
- **models/**: Data models
- **middleware/**: Middleware for authentication, CSRF protection, etc.
- **utils/**: Helper functions, validation, etc.
- **theme_engine/**: WordPress-compatible theme engine

### `/tests` - Test Code

- **test_helper.lua**: Test helper functions
- **test_database.lua**: Database connection and schema tests
- **test_health.lua**: Endpoint tests

### `/docker` - Docker-Related

- **web/Dockerfile**: OpenResty + Lapis + various Lua libraries
- **web/nginx.conf**: Nginx configuration (Lapis compatible)

## Future Implementation Plans

### Phase 1: Core System ✅ Completed
- ✅ User authentication & authorization system (bcrypt)
- ✅ Post CRUD functionality
- ✅ Session management (Redis)
- ✅ CSRF protection

### Phase 2: Theme Compatibility Layer (Lower Priority)
- [ ] WordPress theme loader
- [ ] WordPress function emulation
- [ ] Template engine integration

### Phase 3: Gemini Integration ✅ Completed
- ✅ Gemini API integration
- ✅ Article structure suggestion feature
- ✅ API key encryption management
- ✅ AI proofreading feature

### Phase 4: Admin Panel ✅ Completed
- ✅ Dashboard
- ✅ Post management screen
- ✅ Category and tag management
- ✅ User management
- ✅ Site settings

### Phase 5: Future Enhancements (Under Consideration)

#### Content Features
- [ ] Rich text editor (WYSIWYG)
- [ ] Media upload and management
- [ ] Image optimization
- [ ] Post version control
- [ ] Post duplication feature
- [ ] Bulk operations (delete multiple posts, etc.)

#### AI Feature Enhancements
- [ ] Article SEO analysis
- [ ] Automatic tagging
- [ ] Related post suggestions
- [ ] Image generation (Imagen integration)
- [ ] Multi-language translation

#### User Features
- [ ] Two-factor authentication (2FA)
- [ ] Password reset (via email)
- [ ] OAuth integration (Google/GitHub, etc.)
- [ ] Login history
- [ ] Session management screen

#### Performance
- [ ] Page caching mechanism
- [ ] CDN integration
- [ ] Image lazy loading
- [ ] HTTP/2 Server Push

#### Plugin System
- [ ] Plugin architecture
- [ ] Hooks/filters system
- [ ] Plugin marketplace

#### Monitoring & Analytics
- [ ] Access analytics
- [ ] Error tracking (Sentry integration)
- [ ] Performance monitoring (Prometheus + Grafana)

For detailed implementation plans, refer to [DESIGN.md](DESIGN.md).

## License

This project is released under the [MIT License](LICENSE).

### Why MIT License

1. **High Freedom** - Free for commercial use, modification, and redistribution
2. **Simple** - Short and easy-to-understand license text
3. **Widely Adopted** - Most popular in the open-source community
4. **Compatibility** - Easy to combine with other libraries

The MIT License allows you to freely use, copy, modify, merge, publish, distribute, sublicense, and sell this software.

## References

- [OpenResty Official Documentation](https://openresty.org/)
- [Lapis Official Documentation](https://leafo.net/lapis/)
- [Lua Official Site](https://www.lua.org/)
- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/15/)
- [Redis Official Documentation](https://redis.io/documentation)
- [Busted Official Documentation](https://lunarmodules.github.io/busted/)
- [Docker Official Documentation](https://docs.docker.com/)

## Documentation

### Architecture & Design
- [ARCHITECTURE.md](ARCHITECTURE.md) - System Architecture
- [DESIGN.md](DESIGN.md) - Detailed Design Document

### Feature-Specific Documentation
- [README_ADMIN.md](README_ADMIN.md) - Admin Panel Features
- [README_AUTH.md](README_AUTH.md) - Authentication System
- [README_POST_API.md](README_POST_API.md) - Post API Specification
- [README_THEME_ENGINE.md](README_THEME_ENGINE.md) - Theme Engine

### Testing
- [tests/README.md](tests/README.md) - Test Execution Methods
- [tests/e2e/README.md](tests/e2e/README.md) - E2E Tests
- [tests/integration/README.md](tests/integration/README.md) - Integration Tests

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
