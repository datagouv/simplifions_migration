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

  def migrate_cas_usages
    # print_columns("SIMPLIFIONS_cas_usages", "Cas_d_usages")
  end

  def migrate_solutions
    migrate_public_solutions
  end

  def migrate_public_solutions
    # print_columns("SIMPLIFIONS_produitspublics", "Solutions")
    @solutions_publiques_source ||= @source_grist.records("SIMPLIFIONS_produitspublics")
      .filter { |solution| solution["fields"]["Ref_Nom_de_la_solution"] != "000-data-gouv" }
    solution_targets = @solutions_publiques_source.map do |solution_source|
      transform_public_solution(solution_source)
    end
    @target_grist.create_records("Solutions", solution_targets)
  end

  def migrate_operateurs
    # print_columns("TYPE_nom_administration", "Operateurs")
    # print_columns("Editeurs", "Operateurs")
    fetch_operateurs_publics_source
    fetch_operateurs_prives_source

    operateur_targets = @operateurs_publics_source.map do |operateur_source|
      transform_public_operateur(operateur_source)
    end
    operateur_targets += @operateurs_prives_source.map do |operateur_source|
      transform_private_operateur(operateur_source)
    end
    @target_grist.delete_all_records("Operateurs")
    @target_grist.create_records("Operateurs", operateur_targets)
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
    {
      Nom: source_fields["Nom"],
      Nom_long: source_fields["Nom_long"],
      Public_ou_prive: "Public",
      Type_d_organisation_privee: "",
      Site_internet: nil,
      Lien_Hubspot: nil,
    }
  end

  def transform_private_operateur(operateur_source)
    source_fields = operateur_source["fields"]
    {
      Nom: source_fields["Nom_de_l_editeur"],
      Nom_long: nil,
      Public_ou_prive: "Privé",
      Type_d_organisation_privee: source_fields["Type_d_organisation"],
      Site_internet: source_fields["Site_internet"],
      Lien_Hubspot: source_fields["Lien_Hubspot"],
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
    p source_fields["Ref_Nom_de_la_solution"]
    solution_target = {
      Visible_sur_simplifions: source_fields["Visible_sur_simplifions"],
      Description_courte: source_fields["Description_courte"],
      Description_longue: source_fields["Description_longue"],
      Site_internet: source_fields["URL_Consulter_la_solution_"],
      Nom: source_fields["Ref_Nom_de_la_solution"],
      Operateur: transform_public_operateur_reference(source_fields["Operateur"]),
      Prix: transform_prix(source_fields["Prix_"]), 
      Budget_requis: transform_budget(source_fields["budget"]), 
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

  def transform_public_operateur_reference(operateur_reference)
    fetch_operateurs_publics_source # Fills @operateurs_publics_source if not already filled
    source_operateurs_ids = clean_array(operateur_reference)
    return nil if !source_operateurs_ids

    operateurs_sources = source_operateurs_ids.map { |source_operateur_id| @operateurs_publics_source.find { |operateur| operateur["id"] == source_operateur_id } }
    operateurs_targets = operateurs_sources.map { |operateur_source| @target_grist.find_record("Operateurs", Nom: operateur_source["fields"]["Nom"]) }
    ["L"] + operateurs_targets.map { |operateur_target| operateur_target["id"] }
  end

  def transform_prix(prix_source)
    return nil if prix_source.nil?
    prix_source == "Solution gratuite" ? "Gratuit" : "Payant"
  end

  def transform_budget(budget_source)
    fetch_budgets_target # Fills @budgets_target if not already filled
    budgets_names = clean_array(budget_source)
    return nil if !budgets_names

    budgets_targets = budgets_names.map { |budget_name| @budgets_target.find { |budget| budget["fields"]["Label"] == budget_name } }
    ["L"] + budgets_targets.map { |budget_target| budget_target["id"] }
  end

  def fetch_operateurs_publics_source
    @operateurs_publics_source ||= @source_grist.records("TYPE_nom_administration")
  end

  def fetch_operateurs_prives_source
    @operateurs_prives_source ||= @source_grist.records("Editeurs")
  end

  def fetch_budgets_target
    @budgets_target ||= @target_grist.records("Budgets_de_mise_en_oeuvre")
  end

  def clean_array(array_source)
    return nil if array_source.nil? || array_source.length <= 1
    array_source[1..] # Remove the leading "L"
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

  # migration.migrate_operateurs
  migration.migrate_solutions
end