########################################################################
# File:    loader_helper.rb                                            #
#          Based on work by Hipposoft 2008                             #
#                                                                      #
# Purpose: Support functions for views related to Task Import objects. #
#          See controllers/loader_controller.rb for more.              #
#                                                                      #
# History: 04-Jan-2008 (ADH): Created.                                 #
#          Feb 2009 (SJS): Hacked into plugin for redmine              #
########################################################################

module LoaderHelper
  
  # Generate a project selector for the project to which imported tasks will
  # be assigned. HTML is output which is suitable for inclusion in a table
  # cell or other similar container. Pass the form object being used for the
  # task import view.
  
  def loaderhelp_project_selector( form )
    projectlist = Project.find :all, :conditions => Project.visible_by(User.current)
    
    unless( projectlist.empty? )
      output  = "        &nbsp;Project to which all tasks will be assigned:\n"
      output  << "<select id=\"import_project_id\" name=\"import[project_id]\"><optgroup label=\"Your Projects\"> "
      
      projectlist.each do | projinfo |
        
        output = output + "<option value=\"" + projinfo.id.to_s + "\">" + projinfo.to_s + "</option>"
        
      end
      output << "</optgroup>"
      output << "</select>"
      
      
    else
      output  = "        There are no projects defined. You can create new\n"
      output << "        projects #{ link_to( 'here', '/project/new' ) }."
    end
    
    return output
  end
  
end