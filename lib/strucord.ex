defmodule Strucord do
  require Record

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    from = Keyword.fetch!(opts, :from)

    fields = Record.extract(name, from: from)
    struct_fields = Keyword.keys(fields)
    vars = Macro.generate_arguments(length(struct_fields), __MODULE__)
    kvs = Enum.zip(struct_fields, vars)
    overrides = Keyword.fetch!(opts, :overrides)

    quote do
      defstruct unquote(struct_fields)
      @overrides unquote(overrides)
      @record_field_keys unquote(struct_fields)

      def from_record({unquote(name), unquote_splicing(vars)}) do
        attrs = %{unquote_splicing(kvs)}
        attrs = nested_from_records(attrs, @overrides)
        Kernel.struct(__MODULE__, attrs)
      end

      def to_record(%__MODULE__{unquote_splicing(kvs)} = struct) do
        record = {unquote(name), unquote_splicing(vars)}
        nested_to_records(record, @record_field_keys, struct, @overrides)
      end

      def with_record(%__MODULE__{} = struct, f) when is_function(f, 1) do
        struct
        |> to_record()
        |> f.()
        |> from_record()
      end

      defp nested_from_records(attrs, overrides) do
        override_keys = Keyword.keys(overrides)

        Enum.reduce(override_keys, attrs, fn override_key, acc ->
          override = Keyword.get(overrides, override_key)

          value = do_nested_from_records(attrs, override, override_key)

          Map.put(attrs, override_key, value)
        end)
      end

      defp do_nested_from_records(attrs, override, override_key) do
        case override do
          {:list, child_struct} ->
            record_values = Map.get(attrs, override_key)

            Enum.map(record_values, fn record_value ->
              child_struct.from_record(record_value)
            end)

          child_struct ->
            record_value = Map.get(attrs, override_key)
            child_struct.from_record(record_value)
        end
      end

      defp nested_to_records(record, record_keys, struct, overrides) do
        override_keys = Keyword.keys(overrides)

        Enum.reduce(override_keys, record, fn override_key, acc ->
          override = Keyword.get(overrides, override_key)
          # index of override_key in record tuple
          override_key =
            case is_atom(override_key) do
              true -> override_key
              false -> String.to_existing_atom(override_key)
            end

          index =
            Enum.find_index(record_keys, fn record_key ->
              record_key == override_key
            end)

          case index do
            nil ->
              record

            index ->
              # 0 th position is for the record name, fields start at position 1
              index = index + 1
              value = do_nested_to_records(struct, override, override_key)
              Kernel.put_elem(record, index, value)
          end
        end)
      end

      defp do_nested_to_records(struct, override, override_key) do
        case override do
          {:list, child_struct} ->
            handle_nested_list_records(struct, override_key, child_struct)

          child_struct ->
            value = Map.get(struct, override_key)
            child_struct.to_record(value)
        end
      end

      defp handle_nested_list_records(struct, override_key, child_struct) do
        values = Map.get(struct, override_key)

        case values do
          nil ->
            nil

          values ->
            Enum.map(values, fn struct_value ->
              child_struct.to_record(struct_value)
            end)
        end
      end
    end
  end
end
