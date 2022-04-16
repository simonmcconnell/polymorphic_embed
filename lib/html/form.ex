if Code.ensure_loaded?(Phoenix.HTML) && Code.ensure_loaded?(Phoenix.HTML.Form) do
  defmodule PolymorphicEmbed.HTML.Form do
    import Phoenix.HTML, only: [html_escape: 1]
    import Phoenix.HTML.Form, only: [hidden_inputs_for: 1]

    def poly_inputs_for(%{action: parent_action} = form, field, options)
        when (is_atom(field) or is_binary(field)) and is_list(options) do
          IO.puts "poly inputs for"
          IO.inspect([form, field], label: "[form, field]")
      options =
        form.options
        |> Keyword.take([:multipart])
        |> Keyword.merge(options)
|> IO.inpspect(options)
      my_to_form(form.source, form, field, options)
    end

    def my_to_form(source_changeset, form, field, options) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params || %{}, to_string(field), %{})
      schema = source_changeset.data.__meta__.schema
      %{types_metadata: types_metadata, type_field: type_field} = get_field_options(schema, field)
      type = do_get_polymorphic_module_from_map(params, type_field, schema)
      params = params |> List.wrap()
      list_data = my_get_data(source_changeset, field, type) |> List.wrap()

      list_data
      |> Enum.with_index()
      |> Enum.map(fn {data, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          Ecto.Changeset.change(data)
          |> apply_action(parent_action)

        errors = get_errors(changeset)

        changeset = %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id,
          index: if(length(list_data) > 1, do: i),
          name: name,
          errors: errors,
          data: data,
          params: params,
          hidden: [__type__: to_string(type)],
          options: options
        }
      end)
    end

    defp my_get_data(changeset, field, type) do
      struct = Ecto.Changeset.apply_changes(changeset)

      case Map.get(struct, field) do
        nil ->

          struct(PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type))

        data ->
          data
      end
    end

    defp do_get_polymorphic_module_from_map(%{} = attrs, type_field, types_metadata) do
      attrs = attrs |> convert_map_keys_to_string()

      type = Enum.find_value(attrs, fn {key, value} -> key == type_field && value end)

      if type do
        do_get_polymorphic_module_for_type(type, types_metadata)
      else
        # check if one list is contained in another
        # Enum.count(contained -- container) == 0
        # contained -- container == []
        types_metadata
        |> Enum.filter(&([] != &1.identify_by_fields))
        |> Enum.find(&([] == &1.identify_by_fields -- Map.keys(attrs)))
        |> (&(&1 && Map.fetch!(&1, :module))).()
      end
    end

    defp do_get_polymorphic_module_for_type(type, types_metadata) do
      get_metadata_for_type(type, types_metadata)
      |> (&(&1 && Map.fetch!(&1, :module))).()
    end

    def get_polymorphic_type(schema, field, module_or_struct) do
      %{types_metadata: types_metadata} = get_field_options(schema, field)
      do_get_polymorphic_type(module_or_struct, types_metadata)
    end

    defp do_get_polymorphic_type(%module{}, types_metadata),
      do: do_get_polymorphic_type(module, types_metadata)

    defp do_get_polymorphic_type(module, types_metadata) do
      get_metadata_for_module(module, types_metadata)
      |> Map.fetch!(:type)
      |> String.to_atom()
    end

    defp get_metadata_for_module(module, types_metadata) do
      Enum.find(types_metadata, &(module == &1.module))
    end

    defp get_metadata_for_type(type, types_metadata) do
      type = to_string(type)
      Enum.find(types_metadata, &(type == &1.type))
    end

    defp get_field_options(schema, field) do
      try do
        schema.__schema__(:type, field)
      rescue
        _ in UndefinedFunctionError ->
          raise ArgumentError, "#{inspect(schema)} is not an Ecto schema"
      else
        {:parameterized, PolymorphicEmbed, options} -> Map.put(options, :array?, false)
        {:array, {:parameterized, PolymorphicEmbed, options}} -> Map.put(options, :array?, true)
        {_, {:parameterized, PolymorphicEmbed, options}} -> Map.put(options, :array?, false)
        nil -> raise ArgumentError, "#{field} is not a polymorphic embed"
      end
    end

    defp convert_map_keys_to_string(%{} = map),
      do: for({key, val} <- map, into: %{}, do: {to_string(key), val})

    ##################################

    @spec polymorphic_embed_inputs_for(Phoenix.HTML.Form.t(), Phoenix.HTML.Form.field(), atom) ::
            list(Phoenix.HTML.Form.t())
    def polymorphic_embed_inputs_for(form, field, type),
      do: polymorphic_embed_inputs_for(form, field, type, [])

    @spec polymorphic_embed_inputs_for(
            Phoenix.HTML.Form.t(),
            Phoenix.HTML.Form.field(),
            atom,
            Keyword.t()
          ) :: list(Phoenix.HTML.Form.t())
    def polymorphic_embed_inputs_for(form, field, type, options)
        when (is_atom(field) or is_binary(field)) and is_list(options) do
      options =
        form.options
        |> Keyword.take([:multipart])
        |> Keyword.merge(options)

      to_form(form.source, form, field, type, options)
    end

    @spec polymorphic_embed_inputs_for(
            Phoenix.HTML.Form.t(),
            Phoenix.HTML.Form.field(),
            atom,
            Keyword.t(),
            (Phoenix.HTML.Form.t() -> Phoenix.HTML.unsafe())
          ) :: Phoenix.HTML.safe()
    def polymorphic_embed_inputs_for(form, field, type, options \\ [], fun)
        when (is_atom(field) or is_binary(field)) and is_list(options) and is_function(fun) do
      options =
        form.options
        |> Keyword.take([:multipart])
        |> Keyword.merge(options)

      forms = to_form(form.source, form, field, type, options)

      html_escape(
        Enum.map(forms, fn form ->
          [hidden_inputs_for(form), fun.(form)]
        end)
      )
    end

    def to_form(%{action: parent_action} = source_changeset, form, field, type, options) do
      id = to_string(form.id <> "_#{field}")
      name = to_string(form.name <> "[#{field}]")

      params = Map.get(source_changeset.params || %{}, to_string(field), %{}) |> List.wrap()
      list_data = get_data(source_changeset, field, type) |> List.wrap()

      list_data
      |> Enum.with_index()
      |> Enum.map(fn {data, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          Ecto.Changeset.change(data)
          |> apply_action(parent_action)

        errors = get_errors(changeset)

        changeset = %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id,
          index: if(length(list_data) > 1, do: i),
          name: name,
          errors: errors,
          data: data,
          params: params,
          hidden: [__type__: to_string(type)],
          options: options
        }
      end)
    end

    defp get_data(changeset, field, type) do
      struct = Ecto.Changeset.apply_changes(changeset)

      case Map.get(struct, field) do
        nil ->
          struct(PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type))

        data ->
          data
      end
    end

    # If the parent changeset had no action, we need to remove the action
    # from children changeset so we ignore all errors accordingly.
    defp apply_action(changeset, nil), do: %{changeset | action: nil}
    defp apply_action(changeset, _action), do: changeset

    defp get_errors(%{action: nil}), do: []
    defp get_errors(%{action: :ignore}), do: []
    defp get_errors(%{errors: errors}), do: errors
  end
end
