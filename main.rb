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

    def list_solutions_columns
        puts "Solutions columns:"
        columns = @target_grist.columns("Solutions")
        puts columns.map { |column| column['id'] }

        puts @target_grist.record("Solutions", 5)
    end

    def create_a_solution
        solution_data = {
            Visible_sur_simplifions: true,
            Description_courte: "Description courte de la solution",
            Description_longue: "Description longue de la solution",
            Site_internet: "https://www.solution1.com",
            Nom: "Nom de la solution",
            Operateur: 1,
            Prix: "Gratuit",
            Budget_requis: 1,
            Types_de_simplification: 1,
            A_destination_de: ["L", 2, 3],
            Pour_simplifier_les_demarches_de: 3,
            Cette_solution_permet: "Cette solution permet ceci",
            Cette_solution_ne_permet_pas: "Cette solution ne permet pas cela",
            Image: "Image de la solution",
            Legende_de_l_image: "Legende de l'image",
        }
        record = @target_grist.create_record("Solutions", solution_data)
        puts record
    end
end

# Example usage
if __FILE__ == $0
    migration = SimplifionsMigration.new
    # migration.list_solutions_columns
    migration.create_a_solution
end