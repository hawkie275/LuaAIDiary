# LuaAIDiary

A Lua-based WordPress-like blog system

## Overview

LuaAIDiary is a high-performance blog system built with OpenResty (Nginx + LuaJIT), Lapis, MySQL, and Redis. It provides an easy setup using Docker Compose and a development environment that allows testing during development.

## Key Features

- **High Performance**: Asynchronous I/O processing with OpenResty + Lapis
- **Lightweight**: Fast script execution with LuaJIT
- **Test Environment**: Automated testing support with Busted
- **Developer Tools**: Enhanced development efficiency with Makefile and Luacheck
- **Scalable**: Horizontal scaling with Redis and MySQL
- **Hot Reload**: Automatic reflection of code changes

## Tech Stack

- **Web Framework**: Lapis (OpenResty/Nginx + LuaJIT)
- **Database**: MySQL 8.0
- **Cache/Session**: Redis 7
- **Test Framework**: Busted
- **Static Analysis**: Luacheck
- **Containerization**: Docker & Docker Compose
- **Language**: Lua

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
│       └── luwordpress-default/  # Default theme
├── docker/                    # Docker-related files
│   └── web/
│       ├── Dockerfile         # OpenResty + Lapis environment
│       └── nginx.conf         # Nginx configuration
├── mysql/                     # MySQL-related
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
git clone https://github.com/hawkie275/luwordpress.git
cd luwordpress

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
docker-compose up -d --build

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
make mysql         # MySQL client
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

## Available Endpoints

| Endpoint | Description | Response |
|----------|-------------|----------|
| `GET /` | Homepage | HTML |
| `GET /:slug` | Single post | HTML |
| `GET /health` | Health check | JSON |
| `GET /api/db-test` | MySQL connection test | JSON |
| `GET /api/redis-test` | Redis connection test | JSON |

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
  "mysql_version": "8.0.35",
  "host": "db",
  "database": "luwordpress"
}
```

## Running Tests

### Run all tests

```bash
make test
```

or

```bash
docker-compose exec web busted tests/
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

For detailed schema definitions, refer to [`mysql/init/01_create_tables.sql`](mysql/init/01_create_tables.sql).

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

1. **Change Database Passwords**
   ```bash
   # Change to strong passwords in .env file
   MYSQL_ROOT_PASSWORD=strong_random_password
   MYSQL_PASSWORD=strong_random_password
   ```

2. **Generate Encryption Key**
   ```bash
   # Generate a secure 32-byte key
   openssl rand -hex 32
   
   # Set in .env file
   ENCRYPTION_KEY=generated_key
   ```

3. **Environment Variable Management**
   - **Never commit `.env` file to Git**
   - Verify `.env` is included in `.gitignore`
   - Manage environment variables securely in production (AWS Secrets Manager, Hashicorp Vault, etc.)

4. **Use HTTPS**
   - Always configure HTTPS/TLS in production
   - Free SSL certificates available through Let's Encrypt

### Development Environment Security

Be mindful of the following even in development:

- Default `.env.example` values are for development only
- Don't use personal information or actual API keys
- Don't expose database port (3306) externally

## Environment Variables

Environment variables configurable in `.env` file:

```bash
# MySQL settings
MYSQL_ROOT_PASSWORD=change_this_secure_root_password
MYSQL_DATABASE=luwordpress
MYSQL_USER=luwordpress
MYSQL_PASSWORD=change_this_secure_password

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

If ports 8080, 3306, or 6379 are already in use, change the port settings in `docker-compose.yml`.

### Database Connection Error

```bash
# Check database container status
docker-compose ps db

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

### Phase 1: Core System
- [ ] User authentication & authorization system (bcrypt)
- [ ] Post CRUD functionality
- [ ] Session management (Redis)
- [ ] CSRF protection

### Phase 2: Theme Compatibility Layer
- [x] WordPress theme loader
- [x] WordPress function emulation
- [x] Template engine integration

### Phase 3: Gemini Integration
- [ ] Gemini API integration
- [ ] Article composition suggestion feature
- [ ] API key encryption management

### Phase 4: Admin Panel
- [ ] Dashboard
- [ ] Rich text editor
- [ ] Media upload

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
- [MySQL Official Documentation](https://dev.mysql.com/doc/)
- [Redis Official Documentation](https://redis.io/documentation)
- [Busted Official Documentation](https://lunarmodules.github.io/busted/)
- [Docker Official Documentation](https://docs.docker.com/)

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System Architecture
- [DESIGN.md](DESIGN.md) - Detailed Design Document
- [README_THEME_ENGINE.md](README_THEME_ENGINE.md) - Theme Engine Documentation

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
