defmodule PhxProject.ProductsCtx.ProductReport do
  use TaskBunny.Job

  import Ecto.Changeset

  alias PhxProject.ProductsCtx.Product
  alias PhxProject.ProductsCtx.ProductData

  @headers [:id | Product.get_attrs()] ++ [:inserted_at, :updated_at]
  @prefix "#{File.cwd!}/priv/static/csv/"

  def perform(%{"id" => id} \\ %{"id" => Ecto.UUID.generate()}), do: generate_report(id)

  def generate_report(id \\ Ecto.UUID.generate()) do
    filepath = gen_filepath(id)
    file = File.open!(filepath, [:write, :utf8])

    CSV.encode([@headers], delimiter: "\n")
    |> Enum.each(&IO.write(file, &1))

    ProductData.list()
    |> Enum.map(&product_to_csv_row/1)
    |> CSV.encode(delimiter: "\n")
    |> Enum.each(&IO.write(file, &1))

    File.close(file)

    {:ok, filepath}
  end

  def read_report(filepath) do
    [_ | tail] =
      File.stream!(filepath)
      |> CSV.decode!(headers: @headers)
      |> Enum.map(&csv_row_to_product/1)

    tail
  end

  def send_email(filepath, email_address) do
    url =
      Application.get_env(:phx_project, :email_service_address)
      |> (fn [host: host, port: port] ->
        "#{host}:#{port}/api/send-email/"
      end).()

    body = Poison.encode!(%{
      to: email_address,
      from: "noreply@onboarding.com",
      subject: "[ REPORT ] #{Path.basename(filepath)}",
      body: "Here is your report",
      attachments: [
        %{filename: Path.basename(filepath), content: File.read!(filepath)}
      ]
    })

    headers = [{"content-type", "application/json"}]

    case HTTPoison.post!(url, body, headers) do
      %{status_code: 204} ->
        {:ok, 204, nil}
      res ->
        {:error, res.status_code, res.body}
    end
  end

  def get_reports_dir(), do: @prefix

  def gen_filepath(id) do
    File.mkdir_p!(@prefix)

    @prefix <> "product_report_#{id}.csv"
  end

  defp product_to_csv_row(%Product{} = p) do
    Enum.map(@headers, &Map.get(p, &1))
  end

  defp csv_row_to_product(row) do
    cast(%Product{}, row, @headers)
    |> apply_changes()
  end
end
