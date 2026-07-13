# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# In `:dev`, this loads the demo dataset used for local development and
# feature demos. See AGENTS.md → "Dev seed data".
#
# Re-seed only the demo data (idempotent for users; rebuilds their links):
#
#     mix run priv/repo/demo_seed.exs

if Mix.env() == :dev do
  Code.require_file("demo_seed.exs", __DIR__)
end
