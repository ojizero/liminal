defmodule LiminalWeb.LinkLive.FilterParams do
  @filters [:unviewed, :all, :viewed]
  @sorts [:time_added_desc, :time_added_asc, :expiring_soon]

  def filters, do: @filters
  def sorts, do: @sorts

  def parse_filter("unviewed"), do: {:ok, :unviewed}
  def parse_filter("all"), do: {:ok, :all}
  def parse_filter("viewed"), do: {:ok, :viewed}
  def parse_filter(:unviewed), do: {:ok, :unviewed}
  def parse_filter(:all), do: {:ok, :all}
  def parse_filter(:viewed), do: {:ok, :viewed}
  def parse_filter(_filter), do: :error

  def parse_sort("time_added_desc"), do: {:ok, :time_added_desc}
  def parse_sort("time_added_asc"), do: {:ok, :time_added_asc}
  def parse_sort("expiring_soon"), do: {:ok, :expiring_soon}
  def parse_sort(:time_added_desc), do: {:ok, :time_added_desc}
  def parse_sort(:time_added_asc), do: {:ok, :time_added_asc}
  def parse_sort(:expiring_soon), do: {:ok, :expiring_soon}
  def parse_sort(_sort), do: :error
end
