# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Loads the demo dataset used for local development and feature demos.
# See AGENTS.md → "Dev seed data".
#
# Re-seed anytime (idempotent for users; rebuilds their links):
#
#     mix run priv/repo/demo_seed.exs

Code.require_file("demo_seed.exs", __DIR__)
