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
    puts "\nMigrating cas usages..."
    fetch_cas_d_usages_source # Fills @cas_d_usages_source if not already filled
    cas_usages_targets = @cas_usages_source.map do |cas_usage_source|
      transform_cas_usage(cas_usage_source)
    end
    @target_grist.delete_all_records("Cas_d_usages")
    @target_grist.create_records("Cas_d_usages", cas_usages_targets)
    puts "> #{cas_usages_targets.length} cas usages migrated."
  end

  def migrate_apidata_relations
    puts "\nCleaning api and datasets fournis..."
    @target_grist.delete_all_records("API_et_datasets_fournis")
    @target_grist.delete_all_records("API_et_datasets_integres")

    puts "\nMigrating public api and datasets relations..."
    migrate_apidata_fournies_for_public_products
    migrate_apidata_integrated_for_public_products
    migrate_apidata_integrated_for_private_products
  end

  def migrate_solutions
    puts "\nCleaning solutions..."
    @target_grist.delete_all_records("Solutions")
    migrate_public_solutions
    migrate_private_solutions
    puts "\nCleaning unused attachments..."
    @target_grist.delete_unused_attachments
  end

  def migrate_operateurs
    puts "\nMigrating operateurs..."
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

  def migrate_recommendations
    puts "\nCleaning recommendations..."
    @target_grist.delete_all_records("Recommandations")

    puts "\nMigrating recommendations..."
    fetch_recommendations_sources # Fills @recommendations_sources if not already filled

    recommendations_targets = @recommendations_sources.map do |recommendation_source|
      transform_recommendation_of_solution(recommendation_source)
    end

    @target_grist.create_records("Recommandations", recommendations_targets)
    puts "> #{recommendations_targets.length} recommendations of solutions migrated."
  end

  def migrate_recommendations_of_apidata
    puts "\nMigrating recommendations of apidata..."
    fetch_recommendations_of_apidata_sources # Fills @recommendations_of_apidata_sources if not already filled

    recommendations_of_apidata_source = @recommendations_of_apidata_sources
      .filter { |reco| reco["fields"]["is_inside_a_recommendation"] == false}

    recommendations_targets = recommendations_of_apidata_source.map do |recommendation_of_apidata_source|
      transform_recommendation_of_apidata(recommendation_of_apidata_source)
    end
    @target_grist.create_records("Recommandations", recommendations_targets)
    puts "> #{recommendations_targets.length} recommendations of API or datasets migrated."
  end

  def migrate_apidata_utiles_for_recommendations
    puts "\nCleaning apidata utiles for recommendations..."
    @target_grist.delete_all_records("API_et_datasets_utiles")

    puts "\nMigrating apidata utiles for recommendations..."
    fetch_recommendations_of_apidata_sources # Fills @recommendations_of_apidata_sources if not already filled

    apidata_utiles_source = @recommendations_of_apidata_sources
      .filter { |reco| reco["fields"]["is_inside_a_recommendation"] == true && reco["fields"]["Reco_visible_sur_simplifions"] }

    apidata_utiles_targets = apidata_utiles_source.map do |apidata_utiles_source|
      transform_apidata_utiles(apidata_utiles_source)
    end

    @target_grist.create_records("API_et_datasets_utiles", apidata_utiles_targets)
    puts "> #{apidata_utiles_targets.length} apidata utiles for recommendations migrated."
  end

  def migrate_contacts
    puts "\nCleaning contacts..."
    @target_grist.delete_all_records("Contacts")

    puts "\nMigrating contacts..."
    fetch_contacts_source
    contacts_targets = @contacts_source.map do |contact_source|
      transform_contact(contact_source)
    end

    @target_grist.create_records("Contacts", contacts_targets)
    puts "> #{contacts_targets.length} contacts migrated."
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

  def transform_contact(contact_source)
    source_fields = contact_source["fields"]
    puts "> #{source_fields["Nom"]} #{source_fields["Prenom"]}"

    products = clean_array(source_fields["produits_names"])

    {
      Nom: source_fields["Nom"],
      Prenom: source_fields["Prenom"],
      Email: nil,
      Produits_publics_concernes: ["L"] + products.map { |name| transform_solution_reference(name) },
      Editeur: transform_operateur_reference(source_fields["editeur_name"]),
      Solutions: ["L"] + [transform_solution_reference(source_fields["solution_name"])],
      Notes: source_fields["Note"],
      Role: nil,
    }
  end

  def transform_apidata_utiles(apidata_utiles_source)
    source_fields = apidata_utiles_source["fields"]
    {
      Api_ou_dataset_utile_fourni_par_une_recommandation: transform_apidata_reference(source_fields["apidata_name"]),
      Cas_d_usage: transform_cas_usage_reference(source_fields["cas_usage_name"]),
      En_quoi_cette_API_ou_dataset_est_utile_pour_ce_cas_d_usage: source_fields["Description_de_l_utilisation"],
    }
  end

  def transform_recommendation_of_apidata(recommendation_of_apidata_source)
    source_fields = recommendation_of_apidata_source["fields"]
    puts "> #{source_fields["apidata_name"]} for #{source_fields["cas_usage_name"]}"
    {
      Cas_d_usage: transform_cas_usage_reference(source_fields["cas_usage_name"]),
      Solution_recommandee: nil,
      API_ou_datasets_recommandes: transform_apidata_reference(source_fields["apidata_name"]),
      En_quoi_cette_solution_est_elle_utile_pour_ce_cas_d_usage: source_fields["Description_de_l_utilisation"],
      Visible_sur_simplifions: source_fields["Reco_visible_sur_simplifions"],
      Concretement_pour_les_usagers: nil,
      Concretement_pour_vos_agents: nil,
      Ce_que_ne_fait_pas_cette_solution: nil,
    }
  end

  def transform_recommendation_of_solution(recommendation_source)
    source_fields = recommendation_source["fields"]
    {
      Cas_d_usage: transform_cas_usage_reference(source_fields["cas_usage_name"]),
      Solution_recommandee: transform_solution_reference(source_fields["Nom_de_la_solution_publique"]),
      API_ou_datasets_recommandes: nil,
      En_quoi_cette_solution_est_elle_utile_pour_ce_cas_d_usage: source_fields["En_quoi_cette_solution_est_elle_utile_pour_ce_cas_d_usage_"],
      Visible_sur_simplifions: source_fields["Visible_sur_simplifions"],
      Concretement_pour_les_usagers: source_fields["Concretement_pour_les_usagers_"],
      Concretement_pour_vos_agents: source_fields["Concretement_pour_vos_agents_"],
      Ce_que_ne_fait_pas_cette_solution: source_fields["Ce_que_ne_fait_pas_cette_solution_"],
    }
  end

  def transform_cas_usage_reference(cas_usage_name)
    fetch_cas_d_usages_target # Fills @cas_d_usages_target if not already filled
    cas_usage_target = @cas_d_usages_target.find { |cas_usage| cas_usage["fields"]["Nom"] == cas_usage_name }
    cas_usage_target["id"]
  end

  def transform_cas_usage(cas_usage_source)
    source_fields = cas_usage_source["fields"]
    {
      Icone_du_titre: source_fields["Icone_du_titre"],
      Nom: source_fields["Titre"],
      Description: source_fields["Description_courte"],
      Visible_sur_simplifions: source_fields["Visible_sur_simplifions"],
      Contexte: source_fields["Contexte"],
      Cadre_juridique: source_fields["Cadre_juridique"],
      A_destination_de: transform_fournisseurs_de_service(source_fields["fournisseurs_de_service"]),
      Pour_simplifier_les_demarches_de: transform_usagers(source_fields["target_users"]),
    }
  end

  def migrate_apidata_integrated_for_private_products
    fetch_apidata_private_relations_source
    
    apidata_relations_integrated_targets = @apidata_private_relations_source.map do |apidata_relation_source|
      transform_private_apidata_integrated(apidata_relation_source)
    end

    @target_grist.create_records("API_et_datasets_integres", apidata_relations_integrated_targets)
  end

  def migrate_apidata_fournies_for_public_products
    fetch_apidata_public_relations_source
    apidata_relations_fournies = @apidata_public_relations_source.filter { |apidata_relation| apidata_relation["fields"]["statut_label"] == "🤖 Fournisseur de cette API ou data" }
    
    apidata_relations_fournies_targets = apidata_relations_fournies.map do |apidata_relation_source|
      transform_public_apidata_fournies(apidata_relation_source)
    end

    @target_grist.create_records("API_et_datasets_fournis", apidata_relations_fournies_targets)
  end

  def migrate_apidata_integrated_for_public_products
    fetch_apidata_public_relations_source
    apidata_relations_integrated = @apidata_public_relations_source.filter { |apidata_relation| apidata_relation["fields"]["statut_label"] != "🤖 Fournisseur de cette API ou data" }
    
    apidata_relations_integrated_targets = apidata_relations_integrated.map do |apidata_relation_source|
      transform_public_apidata_integrated(apidata_relation_source)
    end

    @target_grist.create_records("API_et_datasets_integres", apidata_relations_integrated_targets)
  end

  def transform_private_apidata_integrated(apidata_relation_source)
    source_fields = apidata_relation_source["fields"]
    puts "> #{source_fields["solution_editeur"]}"
    {
      Solution_integratrice: transform_solution_reference(source_fields["solution_editeur"]),
      API_ou_dataset_integre: transform_apidata_reference(source_fields["apidata_name"]),
      Status_de_l_integration: source_fields["statut_label"],
      Integre_pour_les_cas_d_usages: transform_cas_usages_reference(source_fields["integre_pour_les_cas_dusages"]),
    }
  end

  def transform_public_apidata_integrated(apidata_relation_source)
    source_fields = apidata_relation_source["fields"]
    puts "> #{source_fields["Api_data_ref"]}"
    {
      Solution_integratrice: transform_solution_reference(source_fields["produit_public"]),
      API_ou_dataset_integre: transform_apidata_reference(source_fields["Api_data_ref"]),
      Status_de_l_integration: source_fields["statut_label"],
      Integre_pour_les_cas_d_usages: transform_cas_usages_reference(source_fields["Utile_pour_les_cas_d_usages"]),
    }
  end

  def transform_public_apidata_fournies(apidata_relation_source)
    source_fields = apidata_relation_source["fields"]
    puts "> #{source_fields["Api_data_ref"]}"
    {
      Solution_fournisseur: transform_solution_reference(source_fields["produit_public"]),
      API_ou_dataset_fourni: transform_apidata_reference(source_fields["Api_data_ref"]),
      Utile_pour_les_cas_d_usages: transform_cas_usages_reference(source_fields["Utile_pour_les_cas_d_usages"]),
    }
  end

  def transform_cas_usages_reference(cas_usages_names)
    cas_usages_names = clean_array(cas_usages_names)
    return nil if !cas_usages_names
    fetch_cas_d_usages_target # Fills @cas_d_usages_target if not already filled

    cas_usages_targets = @cas_d_usages_target.filter { |cas_usages_target| cas_usages_names.include?(cas_usages_target["fields"]["Nom"]) }
    ["L"] + cas_usages_targets.map { |cas_usages_target| cas_usages_target["id"] }
  end


  def transform_solution_reference(solution_fournisseur_name)
    return nil if solution_fournisseur_name == "000-data-gouv" # We don't want to migrate this solution
    fetch_solutions_target # Fills @solutions_target if not already filled
    solution_target = @solutions_target.find { |solution| solution["fields"]["Nom"] == solution_fournisseur_name }
    solution_target["id"]
  end

  def transform_apidata_reference(apidata_name)
    fetch_apidata_target # Fills @apidata_target if not already filled
    return nil if !apidata_name

    apidata_target = @apidata_target.find { |api_and_dataset| api_and_dataset["fields"]["Nom"] == apidata_name }
    raise "Apidata not found in target grist: #{apidata_name}" if !apidata_target
    apidata_target["id"]
  end

  def migrate_public_solutions
    puts "\nMigrating public solutions..."

    fetch_solutions_publiques_source
    solutions_source = @solutions_publiques_source
      .filter { |solution| solution["fields"]["Ref_Nom_de_la_solution"] != "000-data-gouv" } # We don't want to migrate this solutions

    solution_targets = solutions_source.map do |solution_source|
      transform_public_solution(solution_source)
    end

    puts "\nMigrating orphan public solutions..."
    fetch_orphan_solutions_publiques_source
    solution_targets += @orphan_solutions_publiques_source.map do |solution_source|
      transform_orphan_public_solution(solution_source)
    end

    @target_grist.create_records("Solutions", solution_targets)
  end

  def migrate_private_solutions
    puts "\nMigrating private solutions..."

    @solutions_privees_source ||= @source_grist.records("SIMPLIFIONS_solutions_editeurs")

    solution_targets = @solutions_privees_source.map do |solution_source|
      transform_private_solution(solution_source)
    end

    puts "\nMigrating orphan private solutions..."
    fetch_orphan_solutions_privees_source
    solution_targets += @orphan_solutions_privees_source.map do |solution_source|
      transform_orphan_private_solution(solution_source)
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
      Operateur: transform_operateur_reference(source_fields["operateur_nom"]),
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

  def transform_orphan_private_solution(solution_source)
    source_fields = solution_source["fields"]
    puts "> " + source_fields["Nom_du_logiciel_editeur"]
    {
      Visible_sur_simplifions: false,
      Site_internet: source_fields["Site_de_reference"],
      Nom: source_fields["Nom_du_logiciel_editeur"],
      Operateur: transform_operateur_reference(source_fields["operateur_nom"]),
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
    fetch_operateurs_target # Fills @operateurs_target if not already filled

    operateurs_sources = source_operateurs_ids.map { |source_operateur_id| @operateurs_publics_source.find { |operateur| operateur["id"] == source_operateur_id } }
    operateurs_targets = operateurs_sources.map { |operateur_source| @operateurs_target.find { |operateur| operateur["fields"]["Nom"] == operateur_source["fields"]["Nom"] } }
    ["L"] + operateurs_targets.map { |operateur_target| operateur_target["id"] }
  end

  def transform_operateur_reference(source_operateur_nom)
    return nil if !source_operateur_nom
    fetch_operateurs_target # Fills @operateurs_target if not already filled
    operateur_target = @operateurs_target.find { |operateur| operateur["fields"]["Nom"] == source_operateur_nom }
    ["L", operateur_target["id"]]
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
    
    fournisseurs_de_service_targets = fournisseurs_de_service_names.map { |fournisseurs_de_service_name|
      @fournisseurs_de_service_target.find { |fournisseurs_de_service| fournisseurs_de_service["fields"]["slug"] == fournisseurs_de_service_name }
    }
    
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

  def fetch_apidata_target
    @apidata_target ||= @target_grist.records("APIs_et_datasets")
  end

  def fetch_solutions_publiques_source
    @solutions_publiques_source ||= @source_grist.records("SIMPLIFIONS_produitspublics")
  end

  def fetch_orphan_solutions_publiques_source
    @orphan_solutions_publiques_source ||= @source_grist.records("Produitspublics", filter: { has_simplifions_page: [false] })
  end

  def fetch_orphan_solutions_privees_source
    @orphan_solutions_privees_source ||= @source_grist.records("Logiciels_editeurs", filter: { has_simplifions_page: [false] })
  end

  def fetch_apidata_public_relations_source
    @apidata_public_relations_source ||= @source_grist.records("Apidata_DANS_produitspublics")
  end

  def fetch_apidata_private_relations_source
    @apidata_private_relations_source ||= @source_grist.records("Apidata_ET_produitspublics_DANS_logicielsediteurs")
  end

  def fetch_cas_d_usages_target
    @cas_d_usages_target ||= @target_grist.records("Cas_d_usages")
  end

  def fetch_solutions_target
    @solutions_target ||= @target_grist.records("Solutions")
  end

  def fetch_operateurs_target
    @operateurs_target ||= @target_grist.records("Operateurs")
  end

  def fetch_cas_d_usages_source
    @cas_usages_source = @source_grist.records("SIMPLIFIONS_cas_usages")
  end

  def fetch_recommendations_sources
    @recommendations_sources ||= @source_grist.records("SIMPLIFIONS_reco_solutions_cas_usages")
  end

  def fetch_recommendations_of_apidata_sources
    @recommendations_of_apidata_sources ||= @source_grist.records("SIMPLIFIONS_description_apidata_cas_usages")
  end

  def fetch_contacts_source
    @contacts_source ||= @source_grist.records("Contacts_editeurs")
  end

  def clean_array(array_source)
    return [] if array_source.nil? || array_source.length <= 1
    array_source[1..] # Remove the leading "L"
  end
end

# Example usage
if __FILE__ == $0
  migration = SimplifionsMigration.new

  # migration.migrate_operateurs
  # migration.migrate_solutions
  # migration.migrate_cas_usages
  # migration.migrate_apidata_relations
  # migration.migrate_recommendations
  # migration.migrate_recommendations_of_apidata
  # migration.migrate_apidata_utiles_for_recommendations
  migration.migrate_contacts
end