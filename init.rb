require 'redmine'

Redmine::Plugin.register :redmine_loader do

  name 'Basic project file loader for Redmine'

  author 'Simon Stearn largely hacking Andrew Hodgkinsons trackrecord code (sorry Andrew)'

  description 'Basic project file loader'

  version '0.0.9b'

  requires_redmine :version_or_higher => '0.8.0'

  # Commented out because it refused to work in development mode
  default_tracker_name = 'Feature' #Tracker.find_by_id( 1 ).name
  
  settings :default => {'tracker' => default_tracker_name}, :partial => 'settings/loader_settings'

  project_module :project_xml_importer do
    permission :import_issues_from_xml, :loader => [:new, :create]
  end

  menu :project_menu, :loader, { :controller => 'loader', :action => 'new' }, 
    :caption => 'Import Issues', :after => :new_issue, :param => :project_id
end

