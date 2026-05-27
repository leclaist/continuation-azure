# Azure Files SMB doesn't support POSIX fcntl advisory locks that SQLite's
# default WAL mode requires. DELETE journal mode uses simpler dotfile locking
# that works on SMB, and avoids leaving .sqlite3-wal/.sqlite3-shm files that
# persist across container restarts on the network volume.
module SqliteAzureCompat
  def configure_connection
    super
    @raw_connection.busy_timeout(30_000)
    @raw_connection.execute("PRAGMA journal_mode=DELETE")
  end
end

ActiveSupport.on_load(:active_record) do
  require "active_record/connection_adapters/sqlite3_adapter"
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SqliteAzureCompat)
end
