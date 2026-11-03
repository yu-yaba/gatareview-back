# Rails security checks

Dependabot checks the application Gemfile, the separate security-tool Gemfile,
and GitHub Actions every Monday at 09:00 Asia/Tokyo. The `Security checks` workflow
checks both lockfiles with a current ruby-advisory-db and scans the application
with Brakeman. Both CI workflows use a read-only repository token and checkout
does not persist credentials.

The dependency patch updates Rack, Nokogiri, Loofah and rails-html-sanitizer while
preserving the application contract and database schema.

## Code scanning follow-up

The authorization parser now limits the header to 16 KiB and uses disjoint
horizontal-whitespace and non-whitespace token matches. A valid Bearer token
continues to work; oversized headers, extra token data and cookie-only identity
are rejected. Request tests cover those boundaries.

The unused `Api::V1::ApiController` was removed. It inherited from the HTML
controller base and weakened forgery protection with `null_session`. All routed
API controllers already inherit from the application's `ActionController::API`
base and authenticate using the Authorization header. Removing the unused class
does not introduce cookie-based authentication or a new session policy.

Confirm the CodeQL results for the merged default-branch commit after deployment;
a passing RSpec or Brakeman run is not a substitute for that scan.
