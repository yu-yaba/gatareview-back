# Aiven For MySQL Free Migration Runbook

## Goal

- Keep the backend on Heroku.
- Move the production database from JawsDB to Aiven for MySQL Free.
- Keep the frontend pointed at the current backend URL.
- Make rollback possible by switching Heroku env vars only.

## Current And Target State

- Current: `Heroku web + JawsDB`
- Target: `Heroku web + Aiven for MySQL Free`
- Frontend: no Vercel env change is required if the backend URL stays the same

## Required Code State

- Production DB config must prefer `DATABASE_URL` and fall back to `JAWSDB_URL`.
- This repository already contains that fallback behavior in [config/database.yml](/Users/kawaiyuya/Desktop/gatareview/gatareview-back/config/database.yml).

## Preconditions

- Aiven MySQL service is created.
- Aiven connection information is available from the Aiven console.
- The backend code with `DATABASE_URL` support is deployed to Heroku before cutover.
- JawsDB stays attached until the new DB is confirmed stable.

## Environment Variables

- Keep `JAWSDB_URL` unchanged as rollback target.
- Add `DATABASE_URL` on Heroku only at cutover time.
- Keep `FRONTEND_URL`, `JWT_SECRET_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `RECAPTCHA_SECRET_KEY` unchanged.

## Aiven Connection Values

Collect these values from the Aiven console.

- `AIVEN_DB_HOST`
- `AIVEN_DB_PORT`
- `AIVEN_DB_NAME`
- `AIVEN_DB_USER`
- `AIVEN_DB_PASSWORD`
- `AIVEN_DATABASE_URL`

Use the URI from the console as the source of truth for Heroku `DATABASE_URL`.

## Rehearsal

### 1. Capture the current Heroku DB URL

```bash
heroku config:get JAWSDB_URL -a gatareview-back
```

### 2. Dump JawsDB locally

```bash
mkdir -p tmp

mysqldump \
  --single-transaction \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --default-character-set=utf8mb4 \
  -h <JAWSDB_HOST> \
  -P <JAWSDB_PORT> \
  -u <JAWSDB_USER> \
  -p \
  <JAWSDB_DATABASE> > tmp/gatareview_production.sql
```

### 3. Restore into Aiven

```bash
mysql \
  --default-character-set=utf8mb4 \
  -h <AIVEN_DB_HOST> \
  -P <AIVEN_DB_PORT> \
  -u <AIVEN_DB_USER> \
  -p \
  <AIVEN_DB_NAME> < tmp/gatareview_production.sql
```

### 4. Compare table counts

Check at least:

- `lectures`
- `reviews`
- `users`
- `bookmarks`
- `thanks`

### 5. Verify the backend can read from Aiven

Run one-off commands against the backend code with a temporary `DATABASE_URL` override.

```bash
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts ActiveRecord::Base.connection.select_value("SELECT 1")'
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts Lecture.count'
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts Review.count'
```

## Production Cutover

### 1. Enable maintenance mode

```bash
heroku maintenance:on -a gatareview-back
```

### 2. Take the final JawsDB dump

Repeat the dump command used in rehearsal and store it separately as the final cutover dump.

### 3. Re-import the final dump into Aiven

Restore the final dump into the target Aiven database.

### 4. Set Heroku `DATABASE_URL`

```bash
heroku config:set DATABASE_URL='<AIVEN_DATABASE_URL>' -a gatareview-back
```

### 5. Restart dynos

```bash
heroku restart -a gatareview-back
```

### 6. Read-only smoke checks

Check:

- `GET /api/v1/lectures/:id`
- `GET /api/v1/lectures/:id/reviews`
- `GET /api/v1/reviews/latest`
- Google sign-in flow from the frontend

### 7. Confirm writes without persisting new data

Run the review insert test inside a transaction and roll it back.

```bash
heroku run -a gatareview-back "bin/rails runner '
ActiveRecord::Base.transaction do
  lecture = Lecture.joins(:reviews).first || Lecture.first
  Review.create!(
    lecture: lecture,
    rating: 5,
    content: \"Aiven cutover validation review content that is long enough to pass validation.\"
  )
  raise ActiveRecord::Rollback
end
puts :ok
'"
```

This confirms `INSERT` works without keeping test data.

### 8. Disable maintenance mode

```bash
heroku maintenance:off -a gatareview-back
```

## Rollback

If any cutover check fails:

```bash
heroku maintenance:on -a gatareview-back
heroku config:unset DATABASE_URL -a gatareview-back
heroku restart -a gatareview-back
heroku maintenance:off -a gatareview-back
```

Because `JAWSDB_URL` remains attached, the app falls back to the previous DB after restart.

## Post-Cutover

- Keep JawsDB for a few days as a fallback.
- Do not change Vercel `NEXT_PUBLIC_ENV` if the backend host remains unchanged.
- If Aiven Free proves unstable, upgrade the same Aiven service tier rather than migrating again immediately.
