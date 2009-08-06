require 'redmine'

Redmine::Plugin.register :redmine_loader do

  name 'Basic project file loader for Redmine'

  author 'Simon Stearn largely hacking Andrew Hodgkinsons trackrecord code (sorry Andrew)'

  description 'Basic project file loader'

  version '0.0.9'

  requires_redmine :version_or_higher => '0.8.0'

  default_tracker_name = Tracker.find_by_id( 1 ).name
  
  settings :default => {'tracker' => default_tracker_name}, :partial => 'settings/loader_settings'

  menu :top_menu, :loader, { :controller => 'loader', :action => 'new' }, :caption => 'Load Project File', 
	   :if => Proc.new{ User.current.allowed_to?(:edit_project, nil, :global => true) }

end
