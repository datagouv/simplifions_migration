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

  def migrate_api_and_datasets_relations
    puts "Migrating api and datasets..."
    migrate_api_and_datasets_relations_for_public_products
  end

  def migrate_solutions
    "Cleaning solutions..."
    @target_grist.delete_all_records("Solutions")
    migrate_public_solutions
    migrate_private_solutions
    "Cleaning unused attachments..."
    @target_grist.delete_unused_attachments
  end

  def migrate_operateurs
    puts "Migrating operateurs..."
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
    puts "> #{operateur_targets.length} operateurs migrated."
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

  def migrate_api_and_datasets_relations_for_public_products
    @apidata_relations_source ||= @source_grist.records("Apidata_DANS_produitspublics")
    apidata_relations_fournies = @apidata_relations_source.filter { |apidata_relation| apidata_relation["fields"]["statut_label"] == "🤖 Fournisseur de cette API ou data" }
    
    apidata_relations_fournies_targets = apidata_relations_fournies.map do |apidata_relation_source|
      transform_api_and_datasets_fournies(apidata_relation_source)
    end

    # @target_grist.create_records("API_et_datasets_fournis", apidata_relations_fournies_targets)
  end

  def transform_api_and_datasets_fournies(apidata_relation_source)
    source_fields = apidata_relation_source["fields"]
    p "> #{source_fields["Api_data_ref"]}"
    {
      Solution_fournisseur: transform_solution_fournisseur_reference(source_fields["Choix_Produit_public"]),
      API_ou_dataset_fourni: transform_apidata_reference(source_fields["Api_data_ref"]),
      Utile_pour_les_cas_d_usages: nil,
    }
  end

  def transform_solution_fournisseur_reference(solution_fournisseur_id)
    fetch_solutions_publiques_source
    solution_source = @solutions_publiques_source.find { |solution| solution["fields"]["Solution_publique"] == solution_fournisseur_id }
    p solution_fournisseur_id
    p solution_source["fields"]["Ref_Nom_de_la_solution"]
    # TODO : NEED ALL PRODUITS PUBLICS, event those without simplifions solutions.
    solution_target = @target_grist.find_record("Solutions", Nom: solution_source["fields"]["Ref_Nom_de_la_solution"])
    solution_target["id"]
  end

  def transform_apidata_reference(apidata_name)
    fetch_api_and_datasets_target # Fills @api_and_datasets_target if not already filled
    return nil if !apidata_name

    apidata_target = @api_and_datasets_target.find { |api_and_dataset| api_and_dataset["fields"]["Nom"] == apidata_name }
    raise "Apidata not found in target grist: #{apidata_name}" if !apidata_target
    apidata_target["id"]
  end

  def migrate_public_solutions
    puts "Migrating public solutions..."

    fetch_solutions_publiques_source
    solutions_source = @solutions_publiques_source
      .filter { |solution| solution["fields"]["Ref_Nom_de_la_solution"] != "000-data-gouv" } # We don't want to migrate this solutions

    solution_targets = solutions_source.map do |solution_source|
      transform_public_solution(solution_source)
    end

    puts "Migrating orphan public solutions..."
    fetch_orphan_solutions_publiques_source
    solution_targets += @orphan_solutions_publiques_source.map do |solution_source|
      transform_orphan_public_solution(solution_source)
    end

    @target_grist.create_records("Solutions", solution_targets)
  end

  def migrate_private_solutions
    puts "Migrating private solutions..."

    @solutions_privees_source ||= @source_grist.records("SIMPLIFIONS_solutions_editeurs")

    solution_targets = @solutions_privees_source.map do |solution_source|
      transform_private_solution(solution_source)
    end

    @target_grist.create_records("Solutions", solution_targets)
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

    transform_base_solution(source_fields).merge({
      Operateur: transform_public_operateur_reference(source_fields["Operateur"]),
    })
  end

  def transform_private_solution(solution_source)
    source_fields = solution_source["fields"]

    transform_base_solution(source_fields).merge({
      Operateur: transform_private_operateur_reference(source_fields["operateur_nom"]),
    })
  end

  def transform_base_solution(source_fields)
    puts "> " + source_fields["Ref_Nom_de_la_solution"]
    {
      Visible_sur_simplifions: source_fields["Visible_sur_simplifions"],
      Description_courte: source_fields["Description_courte"],
      Description_longue: source_fields["Description_longue"],
      Site_internet: source_fields["URL_Consulter_la_solution_"],
      Nom: source_fields["Ref_Nom_de_la_solution"],
      Prix: transform_prix(source_fields["Prix_"]), 
      Budget_requis: transform_budget(source_fields["budget"]), 
      Types_de_simplification: transform_types_simplifications(source_fields["types_de_simplification"]),
      A_destination_de: transform_usagers(source_fields["target_users"]),
      Pour_simplifier_les_demarches_de: transform_fournisseurs_de_service(source_fields["fournisseurs_de_service"]),
      Cette_solution_permet: source_fields["Cette_solution_permet_"],
      Cette_solution_ne_permet_pas: source_fields["Cette_solution_ne_permet_pas_"],
      Image: transform_and_upload_image(source_fields["Image_principale"]),
      Legende_de_l_image: source_fields["Legende_image_principale"],
    }
  end

  def transform_orphan_public_solution(solution_source)
    source_fields = solution_source["fields"]
    puts "> " + source_fields["Nom_produit_public"]
    {
      Visible_sur_simplifions: false,
      Site_internet: source_fields["Site_internet"],
      Nom: source_fields["Nom_produit_public"],
      Operateur: transform_public_operateur_reference(source_fields["Operateur"]),
      Pour_simplifier_les_demarches_de: transform_fournisseurs_de_service(source_fields["fournisseurs_de_service"]),
      A_destination_de: transform_usagers(source_fields["target_users"]),
    }
  end


  def transform_and_upload_image(image_source)
    source_image_ids = clean_array(image_source)
    return nil if !source_image_ids
    source_image_id = source_image_ids.first
    source_image = @source_grist.download_attachment(source_image_id)
    target_image_ids = @target_grist.create_attachment(source_image)
    ["L"] + target_image_ids
  end

  def transform_public_operateur_reference(operateur_reference)
    fetch_operateurs_publics_source # Fills @operateurs_publics_source if not already filled
    source_operateurs_ids = clean_array(operateur_reference)
    return nil if !source_operateurs_ids

    operateurs_sources = source_operateurs_ids.map { |source_operateur_id| @operateurs_publics_source.find { |operateur| operateur["id"] == source_operateur_id } }
    operateurs_targets = operateurs_sources.map { |operateur_source| @target_grist.find_record("Operateurs", Nom: operateur_source["fields"]["Nom"]) }
    ["L"] + operateurs_targets.map { |operateur_target| operateur_target["id"] }
  end

  def transform_private_operateur_reference(source_operateur_nom)
    fetch_operateurs_prives_source # Fills @operateurs_prives_source if not already filled
    return nil if !source_operateur_nom
    operateur_target = @target_grist.find_record("Operateurs", Nom: source_operateur_nom)
    ["L", operateur_target["id"]]
  end

  def transform_operateur_reference(operateur_reference, operateurs_source)
    source_operateurs_ids = clean_array(operateur_reference)
    return nil if !source_operateurs_ids

    operateurs_sources = source_operateurs_ids.map { |source_operateur_id| operateurs_source.find { |operateur| operateur["id"] == source_operateur_id } }
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

  def transform_types_simplifications(types_simplifications_source)
    fetch_types_simplifications_target # Fills @types_simplifications_target if not already filled
    types_simplifications_names = clean_array(types_simplifications_source)
    return nil if !types_simplifications_names

    types_simplifications_targets = types_simplifications_names.map { |types_simplification_name| @types_simplifications_target.find { |types_simplification| types_simplification["fields"]["Label"] == types_simplification_name } }
    ["L"] + types_simplifications_targets.map { |types_simplification_target| types_simplification_target["id"] }
  end

  def transform_usagers(usagers_source)
    fetch_usagers_target # Fills @usagers_target if not already filled
    usagers_names = clean_array(usagers_source)
    return nil if !usagers_names

    usagers_targets = usagers_names.map { |usagers_name| @usagers_target.find { |usagers| usagers["fields"]["Label"] == usagers_name } }
    ["L"] + usagers_targets.map { |usagers_target| usagers_target["id"] }
  end

  def transform_fournisseurs_de_service(fournisseurs_de_service_source)
    fetch_fournisseurs_de_service_target # Fills @fournisseurs_de_service_target if not already filled
    fournisseurs_de_service_names = clean_array(fournisseurs_de_service_source)
    return nil if !fournisseurs_de_service_names

    fournisseurs_de_service_targets = fournisseurs_de_service_names.map { |fournisseurs_de_service_name| @fournisseurs_de_service_target.find { |fournisseurs_de_service| fournisseurs_de_service["fields"]["slug"] == fournisseurs_de_service_name } }
    ["L"] + fournisseurs_de_service_targets.map { |fournisseurs_de_service_target| fournisseurs_de_service_target["id"] }
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
  
  def fetch_types_simplifications_target
    @types_simplifications_target ||= @target_grist.records("Types_de_simplification")
  end

  def fetch_usagers_target
    @usagers_target ||= @target_grist.records("Usagers")
  end

  def fetch_fournisseurs_de_service_target
    @fournisseurs_de_service_target ||= @target_grist.records("Fournisseurs_de_services")
  end

  def fetch_api_and_datasets_target
    @api_and_datasets_target ||= @target_grist.records("APIs_et_datasets")
  end

  def fetch_solutions_publiques_source
    @solutions_publiques_source ||= @source_grist.records("SIMPLIFIONS_produitspublics")
  end

  def fetch_orphan_solutions_publiques_source
    @orphan_solutions_publiques_source ||= @source_grist.records("Produitspublics", filter: { has_simplifions_page: [false] })
  end

  def clean_array(array_source)
    return nil if array_source.nil? || array_source.length <= 1
    array_source[1..] # Remove the leading "L"
  end
end

# Example usage
if __FILE__ == $0
  migration = SimplifionsMigration.new

  migration.migrate_operateurs
  migration.migrate_solutions
  # migration.migrate_api_and_datasets_relations
end