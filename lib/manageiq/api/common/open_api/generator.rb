module ManageIQ
  module API
    module Common
      module OpenApi
        class Generator
          require 'json'
          require 'manageiq/api/common/graphql'

          PARAMETERS_PATH = "/components/parameters".freeze
          SCHEMAS_PATH = "/components/schemas".freeze

          def path_parts(openapi_path)
            openapi_path.split("/")[1..-1]
          end

          # Let's get the latest api version based on the openapi.json routes
          def api_version
            @api_version ||= Rails.application.routes.routes.each_with_object([]) do |route, array|
              matches = ActionDispatch::Routing::RouteWrapper
                        .new(route)
                        .path.match(/\A.*\/v(\d+.\d+)\/openapi.json.*\z/)
              array << matches[1] if matches
            end.max
          end

          def rails_routes
            Rails.application.routes.routes.each_with_object([]) do |route, array|
              r = ActionDispatch::Routing::RouteWrapper.new(route)
              next if r.internal? # Don't display rails routes
              next if r.engine? # Don't care right now...

              array << r
            end
          end

          def openapi_file
            @openapi_file ||= Rails.root.join("public", "doc", "openapi-3-v#{api_version}.0.json").to_s
          end

          def openapi_contents
            @openapi_contents ||= begin
              JSON.parse(File.read(openapi_file))
            end
          end

          def initialize
            app_prefix, app_name = base_path.match(/\A(.*)\/(.*)\/v\d+.\d+\z/).captures
            ENV['APP_NAME'] = app_name
            ENV['PATH_PREFIX'] = app_prefix
            Rails.application.reload_routes!
          end

          def base_path
            openapi_contents["servers"].first["variables"]["basePath"]["default"]
          end

          def applicable_rails_routes
            rails_routes.select { |i| i.path.start_with?(base_path) }
          end

          def schemas
            @schemas ||= {}
          end

          def build_schema(klass_name)
            schemas[klass_name] = openapi_schema(klass_name)
            "##{SCHEMAS_PATH}/#{klass_name}"
          end

          def parameters
            @parameters ||= {}
          end

          def build_parameter(name, value = nil)
            parameters[name] = value
            "##{PARAMETERS_PATH}/#{name}"
          end

          def openapi_list_description(klass_name, primary_collection)
            primary_collection = nil if primary_collection == klass_name
            {
              "summary"     => "List #{klass_name.pluralize}#{" for #{primary_collection}" if primary_collection}",
              "operationId" => "list#{primary_collection}#{klass_name.pluralize}",
              "description" => "Returns an array of #{klass_name} objects",
              "parameters"  => [
                { "$ref" => "##{PARAMETERS_PATH}/QueryLimit"  },
                { "$ref" => "##{PARAMETERS_PATH}/QueryOffset" },
                { "$ref" => "##{PARAMETERS_PATH}/QueryFilter" }
              ],
              "responses"   => {
                "200" => {
                  "description" => "#{klass_name.pluralize} collection",
                  "content"     => {
                    "application/json" => {
                      "schema" => { "$ref" => build_collection_schema(klass_name) }
                    }
                  }
                }
              }
            }.tap do |h|
              h["parameters"] << { "$ref" => build_parameter("ID") } if primary_collection
            end
          end

          def build_collection_schema(klass_name)
            collection_name = "#{klass_name.pluralize}Collection"
            schemas[collection_name] = {
              "type"       => "object",
              "properties" => {
                "meta"  => { "$ref" => "##{SCHEMAS_PATH}/CollectionMetadata" },
                "links" => { "$ref" => "##{SCHEMAS_PATH}/CollectionLinks"    },
                "data"  => {
                  "type"  => "array",
                  "items" => { "$ref" => build_schema(klass_name) }
                }
              }
            }

            "##{SCHEMAS_PATH}/#{collection_name}"
          end

          def openapi_show_description(klass_name)
            {
              "summary"     => "Show an existing #{klass_name}",
              "operationId" => "show#{klass_name}",
              "description" => "Returns a #{klass_name} object",
              "parameters"  => [{ "$ref" => build_parameter("ID") }],
              "responses"   => {
                "200" => {
                  "description" => "#{klass_name} info",
                  "content"     => {
                    "application/json" => {
                      "schema" => { "$ref" => build_schema(klass_name) }
                    }
                  }
                },
                "404" => {"description" => "Not found"}
              }
            }
          end

          def openapi_destroy_description(klass_name)
            {
              "summary"     => "Delete an existing #{klass_name}",
              "operationId" => "delete#{klass_name}",
              "description" => "Deletes a #{klass_name} object",
              "parameters"  => [{ "$ref" => build_parameter("ID") }],
              "responses"   => {
                "204" => { "description" => "#{klass_name} deleted" },
                "404" => { "description" => "Not found"             }
              }
            }
          end

          def openapi_create_description(klass_name)
            {
              "summary"     => "Create a new #{klass_name}",
              "operationId" => "create#{klass_name}",
              "description" => "Creates a #{klass_name} object",
              "requestBody" => {
                "content"     => {
                  "application/json" => {
                    "schema" => { "$ref" => build_schema(klass_name) }
                  }
                },
                "description" => "#{klass_name} attributes to create",
                "required"    => true
              },
              "responses"   => {
                "201" => {
                  "description" => "#{klass_name} creation successful",
                  "content"     => {
                    "application/json" => {
                      "schema" => { "$ref" => build_schema(klass_name) }
                    }
                  }
                }
              }
            }
          end

          def openapi_update_description(klass_name, verb)
            action = verb == "patch" ? "Update" : "Replace"
            {
              "summary"     => "#{action} an existing #{klass_name}",
              "operationId" => "#{action.downcase}#{klass_name}",
              "description" => "#{action}s a #{klass_name} object",
              "parameters"  => [
                { "$ref" => build_parameter("ID") }
              ],
              "requestBody" => {
                "content"     => {
                  "application/json" => {
                    "schema" => { "$ref" => build_schema(klass_name) }
                  }
                },
                "description" => "#{klass_name} attributes to update",
                "required"    => true
              },
              "responses"   => {
                "204" => { "description" => "Updated, no content" },
                "400" => { "description" => "Bad request"         },
                "404" => { "description" => "Not found"           }
              }
            }
          end
        end
      end
    end
  end
end