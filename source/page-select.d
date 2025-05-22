module pageselect;

import mustache;

alias MustacheEngine!(string) Mustache;

void page_context(int page, int max_pages, Mustache.Context mustache_context) {
  if (page > 2) {
    auto mustache_subcontext = mustache_context.addSubContext("prev_pages");
    mustache_subcontext["prev_page"] = 0;
  }
  for (int i = 2; i > 0; i--) {
    int prev_page = page - i;
    if (prev_page >= 0) {
      auto mustache_subcontext = mustache_context.addSubContext("prev_pages");
      mustache_subcontext["prev_page"] = prev_page;
    }
  }
  for (int i = 1; i < 3; i++) {
    int next_page = page + i;
    if (next_page <= max_pages) {
      auto mustache_subcontext = mustache_context.addSubContext("next_pages");
      mustache_subcontext["next_page"] = next_page;
    }
  }
  if (page < max_pages - 1) {
    auto mustache_subcontext = mustache_context.addSubContext("next_pages");
    mustache_subcontext["next_page"] = max_pages;
  }
}
