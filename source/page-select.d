module pageselect;

import std.stdio;
import std.conv;

import mustache;

alias MustacheEngine!(string) Mustache;

void page_context(ref Mustache.Context mustache_context, string parent_page, int page, int max_pages, int limit, string order = "asc", string order_by = "", string[] available_order_by = []) {
  // Set basic page info
  mustache_context["page"] = page.to!string;
  mustache_context["parent_page"] = parent_page;
  mustache_context["limit"] = limit.to!string;
  mustache_context["order_by"] = order_by;
  mustache_context["order"] = order;

  // Flags for conditional rendering
  if (available_order_by.length > 0) {
    mustache_context.useSection("has_order_by");
    mustache_context.useSection("has_order");
  }
  
  string s_limit = "selected_" ~ limit.to!string;
  mustache_context.useSection(s_limit);
                              
  // Order selection flags
  if (order == "asc")
    mustache_context.useSection("order_a");
  else
    mustache_context.useSection("order_d");
  
  // Order by options
  foreach (opt; available_order_by) {
    auto sub = mustache_context.addSubContext("order_by_options");
    sub["value"] = opt;
    sub["label"] = opt;
    if (opt == order_by) {
      sub.useSection("selected");
    }
  }

  // Previous pages
  if (page > 2) {
    auto sub = mustache_context.addSubContext("prev_pages");
    sub["prev_page"] = "0";
  }
  for (int i = 2; i > 0; i--) {
    int prev_page = page - i;
    if (prev_page >= 0) {
      auto sub = mustache_context.addSubContext("prev_pages");
      sub["prev_page"] = prev_page.to!string;
    }
  }

  // Next pages
  for (int i = 1; i < 3; i++) {
    int next_page = page + i;
    if (next_page <= max_pages) {
      auto sub = mustache_context.addSubContext("next_pages");
      sub["next_page"] = next_page.to!string;
    }
  }
  if (page < max_pages - 1) {
    auto sub = mustache_context.addSubContext("next_pages");
    sub["next_page"] = max_pages.to!string;
  }
}
