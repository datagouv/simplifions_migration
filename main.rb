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

  def migrate_solutions
    @solutions_source = @source_grist.records("SIMPLIFIONS_produitspublics")
    solution_targets = @solutions_source.map do |solution_source|
      transform_public_solution(solution_source)
    end
    @target_grist.create_records("Solutions", solution_targets)
  end

  def migrate_operateurs
    print_columns("Produitspublics", "Operateurs")
  end

  private

  def print_columns(source_table, target_table)
    puts "Source columns of #{source_table}:"
    puts @source_grist.columns(source_table)
      .map { |column| column["id"] }
    puts "--------------------------------"
    puts "Target columns of #{target_table}:"
    puts @target_grist.columns(target_table)
      .filter{ |column| column["fields"]["formula"].length == 0 }
      .map { |column| 
        [
          column["id"],
          column["fields"]["type"].start_with?("Ref") ? "nil," : "source_fields[\"\"],"
        ].join(": ")
      }
    puts "--------------------------------"
  end

  def transform_public_operateur(operateur_source)
    source_fields = operateur_source["fields"]
    operateur_target = {
      Nom: source_fields["Nom_produit_public"],
      Nom_long: source_fields["Nom_long"],
      Public_ou_prive: "Public",
      Type_d_organisation_privee: nil,
      Site_internet: nil,
      Lien_Hubspot: nil,
    }
  end

  def transform_cas_d_usage(cas_d_usage_source)
    source_fields = cas_d_usage_source["fields"]
    cas_d_usage_target = {
      "Icone_du_titre" => source_fields["Icone_du_titre"],
      "Nom" => source_fields["Titre"],
      "Description" => source_fields["Description"],
      "Visible_sur_simplifions" => source_fields["Visible_sur_simplifions"],
      "Contexte" => source_fields["Contexte"],
      "Cadre_juridique" => source_fields["Cadre_juridique"],
      "A_destination_de_" => nil,
      "Pour_simplifier_les_demarches_de" => nil,
      "Recommandations" => nil
    }
    cas_d_usage_target
  end

  def transform_public_solution(solution_source)
    source_fields = solution_source["fields"]
    solution_target = {
      Visible_sur_simplifions: source_fields["Visible_sur_simplifions"],
      Description_courte: source_fields["Description_courte"],
      Description_longue: source_fields["Description_longue"],
      Site_internet: source_fields["URL_Consulter_la_solution_"],
      Nom: source_fields["Ref_Nom_de_la_solution"],
      Operateur: nil,
      Prix: nil, # Prix_ 
      Budget_requis: nil, 
      Types_de_simplification: nil,
      A_destination_de: nil,
      Pour_simplifier_les_demarches_de: nil,
      Cette_solution_permet: source_fields["Cette_solution_permet_"],
      Cette_solution_ne_permet_pas: source_fields["Cette_solution_ne_permet_pas_"],
      Image: nil,
      Legende_de_l_image: source_fields["Legende_image_principale"],
    }
    solution_target
  end

  # def create_attachment
  #  # Create an attachment in the target grist
  #  file_path = "Sample Image.png"
   
  #  file = File.open(file_path, 'rb')
   
  #  begin
  #   # Try different approaches for the upload parameter
  #   attachments = @target_grist.create_attachment(file)
  #   puts "Attachment created successfully!"
  #   puts "Full response: #{attachments}"
  #  ensure
  #   file.close
  #  end
  # end
end

# Example usage
if __FILE__ == $0
  migration = SimplifionsMigration.new
  # migration.migrate_solutions

  migration.migrate_operateurs

  # migration.print_columns("SIMPLIFIONS_cas_usages", "Cas_d_usages")
  # migration.print_columns("SIMPLIFIONS_produitspublics", "Solutions")
end