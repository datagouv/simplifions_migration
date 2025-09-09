require_relative 'grist_api'

SOURCE_GRIST_ID = "c5pt7QVcKWWe"
TARGET_GRIST_ID = "ofSVjCSAnMb6"
GRIST_API_KEY = ENV['SECRET_GRIST_API_KEY']
GRIST_API_URL = "https://grist.numerique.gouv.fr/api"

class SimplifionsMigration
    def initialize
        @source_grist = GristApi.new(
            api_url: GRIST_API_URL,
            api_key: GRIST_API_KEY,
            document_id: SOURCE_GRIST_ID
        )
        @target_grist = GristApi.new(
            api_url: GRIST_API_URL,
            api_key: GRIST_API_KEY,
            document_id: TARGET_GRIST_ID
        )
    end

    def list_tables
        puts "Source tables:"
        source_tables = @source_grist.tables
        puts source_tables.map { |table| table['id'] }
        list_columns(source_tables.first['id'])

        puts "\n\nTarget tables:"
        target_tables = @target_grist.tables
        puts target_tables.map { |table| table['id'] }
    end

    def list_columns(table_id)
        puts "Columns for table '#{table_id}':"
        columns = @source_grist.columns(table_id)
        puts columns.map { |column| column['id'] }
    end
end

# Example usage
if __FILE__ == $0
    migration = SimplifionsMigration.new
    migration.list_tables
end