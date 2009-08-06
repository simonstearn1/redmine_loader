########################################################################
# File:    loader.rb                                                   #
#          Based on work by Hipposoft 2008                             #
#                                                                      #
# Purpose: Encapsulate data required for a loader session.             #
#                                                                      #
# History: 16-May-2008 (ADH): Created.                                 #
#          Feb 2009 (SJS): Hacked into plugin for redmine              #
########################################################################

class TaskImport
  @tasks      = []
  @project_id = nil

  attr_accessor( :tasks, :project_id )
end
