# The preceding official APT buildpack profile adds .apt to LD_LIBRARY_PATH.
# Verify executable code before Ruby loads the vendored native library.
if ! "$HOME/bin/verify-mysql-client-files" "$HOME"; then
  exit 1
fi
export LIBMYSQL_PLUGIN_DIR="$HOME/.apt/usr/lib/mysql/plugin"
