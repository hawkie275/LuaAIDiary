# LuaAIDiary

A Lua/OpenResty-based WordPress-like blog system with an admin panel, JSON APIs, Gemini-powered writing support, and local image media management.

Japanese documentation is available in [`README_JP.md`](README_JP.md).

## Overview

LuaAIDiary is a blog/CMS application built on OpenResty, LuaJIT, Lapis, PostgreSQL, and Valkey. It provides WordPress-like public URLs, an authenticated admin UI for content management, REST-like APIs for posts/categories/tags/media/authentication, and Docker Compose-based local development.

The current implementation includes admin content management, authentication/authorization, Gemini AI support, and Phase 1 local image upload support backed by PostgreSQL metadata and a Docker volume.

## Implemented Features

### Public blog frontend

- Home page, single post pages, category archives, tag archives, author archives, date archives, search results, and 404 handling.
- WordPress-like routing such as `/`, `/posts/:slug`, `/category/:slug`, `/tag/:slug`, `/author/:username`, `/search`, and date archive paths.
- Sidebar post search form on the post list and single post pages for searching published posts by partial matches in the title, excerpt, and content.
- Search requests use URLs such as `/search?s=keyword`, and results are rendered responsively inside the search results page sidebar.
- Basic public rendering through the public controller path currently wired in [`app/init.lua`](app/init.lua).

### Admin panel

- Login/logout and password change screens.
- Dashboard with site statistics, recent posts, and system information.
- Post list/create/edit/delete flows with draft/published/trash status, categories, tags, Markdown preview, and media picker integration.
- Category and tag management.
- User management for administrators and profile editing for authenticated users.
- Site settings and AI preference/API key management.
- Media library screen for image uploads, search, rename, deletion, and usage status.

### APIs

- Authentication API: register, login, logout, current user, password change, and auth status check.
- CSRF token endpoint for state-changing requests.
- Post CRUD API with category/tag assignment and ownership checks.
- Category and tag CRUD APIs with role-based permissions.
- Media API for image upload, listing, detail, rename, and logical deletion.
- Markdown preview API.
- Gemini API endpoints for article generation, proofreading, and connection testing.
- AI settings API for user preferences and encrypted Gemini API key storage.

### Authentication and security

- Session-based authentication backed by Valkey.
- Role-based access control using `admin`, `editor`, `author`, and `subscriber` roles.
- CSRF protection for state-changing APIs and admin forms.
- Password hashing through the authentication service.
- Gemini API keys are stored through the user settings model with encryption support.

### Media upload

- Local image upload for `jpg`, `jpeg`, `png`, `webp`, and `gif`.
- Admin media library and post editor media picker.
- Metadata storage in `media` and `media_post_usages` tables.
- SHA-256 duplicate detection and active media reuse.
- Thumbnail generation uses `vips`/`vipsheader` when available, with fallback to the original image URL when thumbnail generation fails.
- Logical deletion with protection for media referenced by posts; post create/update synchronizes `/uploads/...` references into `media_post_usages`.
- Uploaded files are stored in the `media_uploads` Docker volume mounted at `/app/uploads`.

### Database and caching

- PostgreSQL initialization scripts for users, posts, comments, categories, tags, user settings, sample data, AI settings, performance indexes, and media tables.
- PostgreSQL full-text search index on post title/content.
- Valkey is used for sessions and cache-related services.

## Tech Stack

- **Language**: Lua
- **Runtime/Web server**: OpenResty + LuaJIT + Nginx
- **Web framework**: Lapis
- **Database**: PostgreSQL 18
- **Session/cache store**: Valkey 9
- **Templates**: ETV Lua templates for the admin UI and Lua/public rendering code
- **AI integration**: Google Gemini API
- **Testing**: Busted, shell-based E2E tests, integration tests
- **Static analysis**: Luacheck
- **Containerization**: Docker and Docker Compose

## Project Structure

```text
LuaAIDiary/
├── app/
│   ├── init.lua                 # Lapis application and routes
│   ├── controllers/             # Public, API, admin, auth, media, Gemini controllers
│   ├── models/                  # Database models
│   ├── services/                # Auth, cache, Gemini services
│   ├── middleware/              # Auth, CSRF, page cache middleware
│   ├── theme_engine/            # Experimental/incomplete theme-related code
│   ├── utils/                   # Crypto, Markdown, session, slug, validator utilities
│   └── views/admin/             # Admin UI templates
├── docker/web/                  # OpenResty image and Nginx configuration
├── docs/                        # Feature and design documents
├── postgresql/init/             # Initial database scripts
├── postgresql/migrations/       # Additional migrations for existing databases
├── static/                      # Admin CSS/JavaScript and static assets
├── tests/                       # Unit, integration, E2E, performance, and related tests
├── wp-content/themes/           # Experimental theme assets retained in the repo
├── docker-compose.yml
├── Makefile
├── README.md
└── README_JP.md
```

## Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- Make, recommended for common development tasks

### Recommended setup

```bash
git clone https://github.com/hawkie275/LuaAIDiary.git
cd LuaAIDiary
make setup
```

`make setup` creates `.env` from `.env.example` if needed, pulls the latest web image from GHCR, synchronizes `APP_VERSION`, starts services, and waits briefly for the database.

For a local image build instead of pulling from GHCR:

```bash
make setup-build
```

### Manual setup

```bash
cp .env.example .env
docker compose up -d --build
sleep 10
```

### Access URLs

- Public site: <http://localhost:8080>
- Admin panel: <http://localhost:8080/admin>
- Health check: <http://localhost:8080/health>

Default admin user data is initialized by the PostgreSQL scripts. Check [`postgresql/init/01_create_tables.sql`](postgresql/init/01_create_tables.sql) and [`postgresql/init/02_update_admin_password.sql`](postgresql/init/02_update_admin_password.sql), then change the password after first login.

## Main Make Commands

```bash
make help              # Show available commands
make setup             # Initial setup using the GHCR web image
make setup-build       # Initial setup with a local Docker build
make dev               # Start services in the foreground
make build             # Build Docker images without cache
make up                # Start services in the background
make down              # Stop services
make restart           # Restart services
make logs              # Follow all service logs
make logs-web          # Follow web logs
make logs-db           # Follow PostgreSQL logs
make logs-redis        # Follow Valkey logs
make shell             # Open a shell in the web container
make shell-lua         # Start a Lua shell in the web container
make shell-db          # Open a shell in the DB container
make psql              # Open PostgreSQL client
make redis-cli         # Open Valkey/Redis CLI
make migrate           # Apply media-table migration to an existing DB
make health            # Check /health
make status            # Show Docker Compose service status
make db-reset          # Reset database after confirmation
make clean             # Remove containers and volumes after confirmation
```

## Testing and Quality Checks

Services must be running for E2E and integration tests.

```bash
make up
make health
make test              # Runs E2E tests through make test-e2e
make test-e2e          # Runs post API and media API E2E scripts
make test-integration  # Runs integration tests against the real DB
make test-all          # Runs the configured E2E test target
make test-file FILE=/tests/path/to/spec.lua
make lint              # Run Luacheck for app/ and tests/
```

Notable test areas:

- [`tests/e2e`](tests/e2e): HTTP-based E2E tests for posts, media, auth/admin flows, categories/tags, password change, and user management.
- [`tests/controllers`](tests/controllers): controller specs.
- [`tests/models`](tests/models): model specs.
- [`tests/middleware`](tests/middleware): CSRF middleware specs.
- [`tests/theme_engine`](tests/theme_engine): tests for experimental theme-related code retained in the repository.
- [`tests/integration`](tests/integration): real database integration tests.
- [`tests/performance`](tests/performance): benchmark scripts and reports.

## Available Endpoints

### Public Endpoints

| Route | Purpose |
| --- | --- |
| `/` | Home/post list |
| `/posts/:slug` | Single post |
| `/category/:slug` | Category archive |
| `/tag/:slug` | Tag archive |
| `/author/:username` | Author archive |
| `/search?s=keyword` | Search published posts by title, excerpt, or content and show responsive sidebar results |
| `/:year`, `/:year/:month`, `/:year/:month/:day` | Date archives |

### Authentication API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/auth/register` | POST | Register a user | No |
| `/api/auth/login` | POST | Login | No |
| `/api/auth/logout` | POST | Logout | Yes |
| `/api/auth/me` | GET | Get current user | Yes |
| `/api/auth/change-password` | POST | Change password | Yes |
| `/api/auth/check` | GET | Check authentication status | Optional |
| `/api/csrf-token` | GET | Get CSRF token | Session-based |

### Post API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/posts` | GET | List posts | Optional |
| `/api/posts` | POST | Create post | Yes |
| `/api/posts/:id` | GET | Get post detail | Optional, draft restricted |
| `/api/posts/:id` | PUT | Update post | Owner |
| `/api/posts/:id` | DELETE | Delete post | Owner |

### Category API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/categories` | GET | List categories | No |
| `/api/categories` | POST | Create category | Editor or admin |
| `/api/categories/:id` | GET | Get category detail | No |
| `/api/categories/:id` | PUT | Update category | Editor or admin |
| `/api/categories/:id` | DELETE | Delete category | Editor or admin |

### Tag API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/tags` | GET | List tags | No |
| `/api/tags` | POST | Create tag | Author or higher |
| `/api/tags/:id` | GET | Get tag detail | No |
| `/api/tags/:id` | PUT | Update tag | Editor or admin |
| `/api/tags/:id` | DELETE | Delete tag | Editor or admin |

### Media API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/media` | GET | List uploaded images with pagination/search | Editor or admin |
| `/api/media` | POST | Upload image with multipart form-data | Editor or admin + CSRF |
| `/api/media/:id` | GET | Get image metadata | Editor or admin |
| `/api/media/:id` | PATCH | Rename image/update alt text | Editor or admin + CSRF |
| `/api/media/:id` | DELETE | Logically delete unused image | Editor or admin + CSRF |

Supported image formats are `jpg`, `jpeg`, `png`, `webp`, and `gif`. Media metadata is stored in PostgreSQL, while file data is stored locally under `/app/uploads` via the `media_uploads` Docker volume.

Current media API behavior:

- Upload request field: multipart `file` is required; `alt_text` is optional.
- New uploads return `201` with `success`, `id`, `file_name`, `url`, `thumbnail_url`, `mime_type`, `size_bytes`, `width`, `height`, `alt_text`, `usage_count`, `in_use`, and `deduplicated`.
- Duplicate uploads are detected by SHA-256 and return the existing active media with `200` and `deduplicated: true`.
- `GET /api/media` accepts `page`, `per_page`, and `q` query parameters.
- `PATCH /api/media/:id` requires `file_name`; `alt_text` can also be updated.
- `DELETE /api/media/:id` returns `409` if the media is currently referenced by a post.
- Upload validation returns `413` for files over the current 10 MB limit and `415` for unsupported extension/MIME mismatches.

### Admin Panel Endpoints

| Route | Purpose |
| --- | --- |
| `/admin/login` | Login screen |
| `/admin` | Redirect to dashboard |
| `/admin/dashboard` | Dashboard |
| `/admin/posts` | Post management |
| `/admin/posts/new` | New post form |
| `/admin/posts/:id/edit` | Edit post form |
| `/admin/categories` | Category management |
| `/admin/tags` | Tag management |
| `/admin/media` | Media library |
| `/admin/users` | User management |
| `/admin/users/new` | New user form |
| `/admin/users/:id/edit` | Edit user form |
| `/admin/profile` | User profile |
| `/admin/profile/edit` | Edit current profile |
| `/admin/settings` | Site and AI settings |
| `/admin/change-password` | Password change |

### Gemini AI API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/gemini/generate-article` | POST | Generate article content | Yes + CSRF |
| `/api/gemini/proofread` | POST | Proofread/improve article content | Yes + CSRF |
| `/api/gemini/test-connection` | POST | Test Gemini API connection | Yes + CSRF |

### AI Settings API Endpoints

| Endpoint | Method | Description | Auth |
| --- | --- | --- | --- |
| `/api/settings/ai-preferences` | GET | Get current AI preferences | Yes |
| `/api/settings/ai-preferences/defaults` | GET | Get default AI preferences | Yes |
| `/api/settings/ai-preferences` | PUT | Update AI preferences | Yes + CSRF |
| `/api/settings/gemini-api-key` | POST | Save Gemini API key | Yes + CSRF |
| `/api/settings/gemini-api-key` | DELETE | Delete Gemini API key | Yes + CSRF |

### Other Endpoints

| Endpoint | Method | Description |
| --- | --- | --- |
| `/health` | GET | Health check |
| `/api/db-test` | GET | PostgreSQL connection test |
| `/api/redis-test` | GET | Valkey connection test |
| `/api/models-test` | GET | Model loading check |
| `/api/preview/markdown` | POST | Markdown preview for admin editor |

### Example: Health Check

```bash
curl http://localhost:8080/health
```

Example response:

```json
{
  "status": "ok",
  "service": "LuaAIDiary",
  "version": "0.1.0",
  "timestamp": 1760000000
}
```

### Example: Database Connection Test

```bash
curl http://localhost:8080/api/db-test
```

Example response:

```json
{
  "status": "success",
  "message": "データベース接続成功",
  "postgres_version": "PostgreSQL ...",
  "database": "luaaidiary",
  "host": "db"
}
```

## Database Notes

Fresh containers run all scripts in [`postgresql/init`](postgresql/init). Existing databases can apply the media table migration with:

```bash
make migrate
```

Media upload metadata is created by [`postgresql/init/06_add_media_tables.sql`](postgresql/init/06_add_media_tables.sql), and the equivalent existing-DB migration is [`postgresql/migrations/001_add_media_tables.sql`](postgresql/migrations/001_add_media_tables.sql).

### Main Tables

- `users`: user accounts and roles.
- `posts`: blog posts with `draft`, `published`, and `trash` statuses.
- `comments`: comment data and moderation status.
- `categories`, `tags`: taxonomy data.
- `post_categories`, `post_tags`: post-taxonomy relationships.
- `user_settings`: AI preferences and Gemini API key storage.
- `post_meta`: custom post metadata.
- `media`: uploaded image metadata.
- `media_post_usages`: relationships between posts and referenced media, synchronized from `/uploads/...` URLs in post content.

## Development Workflow

### Hot Reload

In development, application files are mounted into the web container through the Docker image/build context and OpenResty/Lapis reflects changes after reload/restart as needed. Use `make dev` for foreground development and `make restart` when a container restart is required.

### Static Analysis

```bash
make lint
```

Luacheck runs against [`app`](app) and [`tests`](tests).

### Database Reset

```bash
make db-reset
```

This command asks for confirmation and recreates the database using the initialization scripts. It deletes existing application data.

### Log Monitoring

```bash
make logs
make logs-web
make logs-db
make logs-redis
```

## Security

### Important Settings for Production

Before production use, review at least the following:

- Change default administrator credentials.
- Set strong `POSTGRES_PASSWORD` and application secrets in `.env`.
- Set and protect the encryption key used for Gemini API key storage.
- Restrict exposed database/cache ports if they are not needed externally.
- Use HTTPS through a reverse proxy or load balancer.
- Review upload size limits and accepted MIME types for media upload.

### Implemented Security Features

#### Password Security

- Password hashing is handled by the authentication service.
- Password change is available through both API and admin UI.

#### Session Management

- Session data is stored in Valkey.
- Authentication state is checked by controllers and middleware.

#### CSRF Protection

- CSRF tokens are generated and verified for state-changing requests.
- The token can be retrieved from `/api/csrf-token` for API usage.

#### API Key Encryption

- Gemini API key storage is handled via the user settings model and crypto utilities.
- Each user manages their own Gemini API key.

#### Role-Based Access Control

- Admin dashboard and media library require `admin` or `editor`.
- User management is limited to `admin`.
- Post/category/tag APIs and admin actions apply role and ownership checks.

#### Input Validation

- Controllers validate required fields, IDs, status values, and media constraints.
- Media upload validates extension/MIME compatibility and size constraints.

## Environment Variables

Create `.env` from [`.env.example`](.env.example). Key variables include:

| Variable | Purpose |
| --- | --- |
| `POSTGRES_DB` | PostgreSQL database name |
| `POSTGRES_USER` | PostgreSQL user |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `IMAGE_TAG` | Web image tag used by Docker Compose/GHCR workflow |
| `APP_VERSION` | Application version displayed in admin system info |
| `ENCRYPTION_KEY` | Key material for encrypted secret storage, when configured |

Runtime container variables such as `POSTGRES_HOST`, `POSTGRES_PORT`, `REDIS_HOST`, `REDIS_PORT`, and `LAPIS_ENVIRONMENT` are provided by [`docker-compose.yml`](docker-compose.yml).

## Troubleshooting

### Services Won't Start

```bash
make status
make logs
```

Check whether Docker is running, `.env` exists, and required ports are available.

### Ports Already in Use

The default service ports are:

- Web: `8080`
- PostgreSQL: `5432`
- Valkey: `6379`

Change port mappings in [`docker-compose.yml`](docker-compose.yml) if another process already uses them.

### Database Connection Error

```bash
make logs-db
make psql
curl http://localhost:8080/api/db-test
```

Verify `POSTGRES_*` values in `.env` and confirm that the `db` service is healthy.

### Tests Fail

```bash
make up
make health
make test-e2e
```

E2E tests require the application to be running at the expected base URL. Some scripts also create temporary users or content.

### Media Upload Fails

- Confirm that the file is one of `jpg`, `jpeg`, `png`, `webp`, or `gif`.
- Confirm that the file size is within the configured upload limit.
- Check web logs with `make logs-web`.
- For existing databases, confirm that `make migrate` has been applied.
- If deletion fails with `409`, remove the image reference from posts first so usage synchronization can clear it.

### Container Build Error

```bash
make build
make logs-web
```

If using the registry image path, run `make setup`. If developing local Docker changes, run `make setup-build`.

## Related Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md): architecture overview.
- [`DESIGN.md`](DESIGN.md): detailed design notes.
- [`README_ADMIN.md`](README_ADMIN.md): admin dashboard implementation notes.
- [`README_AUTH.md`](README_AUTH.md): authentication system documentation.
- [`README_POST_API.md`](README_POST_API.md): post API documentation.
- [`docs/media_upload_feature_spec.md`](docs/media_upload_feature_spec.md): media upload feature specification.
- [`docs/media_upload_design.md`](docs/media_upload_design.md): media upload implementation design.
- [`tests/e2e/README.md`](tests/e2e/README.md): E2E testing guide.
- [`tests/integration/README.md`](tests/integration/README.md): integration testing guide.
- [`tests/performance/README.md`](tests/performance/README.md): performance testing guide.

## License

MIT License. See [`LICENSE`](LICENSE).
