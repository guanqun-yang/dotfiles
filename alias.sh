# Launch QuickSearch app with conda environment
quicksearch() {
    cd /Users/yang/QuickSearch && conda activate QuickSearch && python run.py
}

# Sync Zotero Meilisearch index for MCP server
zotero-sync() {
    /opt/anaconda3/envs/SeekZotero/bin/python /Users/yang/SeekZotero/scripts/sync_index.py "$@"
}
