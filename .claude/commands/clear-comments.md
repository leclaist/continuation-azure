Clear all generated comments from production so they regenerate with the current prompt on next visit.

Run: `fly ssh console --command "/rails/bin/rails runner 'puts \"Deleted #{GeneratedComment.delete_all} comments\"'"`

Report how many were deleted.
