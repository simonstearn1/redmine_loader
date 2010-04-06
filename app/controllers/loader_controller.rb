########################################################################
# File:    loader_controler.rb                                         #
#          Hipposoft 2008                                              #
#                                                                      #
# History: 04-Jan-2008 (ADH): Created.                                 #
#          Feb 2009 (SJS): Hacked into plugin for redmine              #
########################################################################

class TaskImport
  @tasks      = []
  @project_id = nil
  @new_categories = []
  
  attr_accessor( :tasks, :project_id, :new_categories )
end

class LoaderController < ApplicationController
  
  unloadable

  before_filter :find_project, :authorize, :only => [:new, :create]  

  require 'zlib'
  require 'ostruct'
  require 'tempfile'
  require 'rexml/document'
  
  # Set up the import view. If there is no task data, this will consist of
  # a file entry field and nothing else. If there is parsed file data (a
  # preliminary task list), then this is included too.
  
  def new
    # This can and probably SHOULD be replaced with some URL rewrite magic
    # now that the project loader is Redmine project based.
    find_project()
  end
  
  # Take the task data from the 'new' view form and 'create' an "import
  # session"; that is, create real Task objects based on the task list and
  # add them to the database, wrapped in a single transaction so that the
  # whole operation can be unwound in case of error.
  
  def create
    # This can and probably SHOULD be replaced with some URL rewrite magic
    # now that the project loader is Redmine project based.
    find_project()

    # Set up a new TaskImport session object and read the XML file details
    
    xmlfile = params[ :import ][ :xmlfile ]
    @import = TaskImport.new
        
    unless ( xmlfile.nil? )

      # The user selected a file to upload, so process it
      
      begin
        
        # We assume XML files always begin with "<" in the first byte and
        # if that's missing then it's GZip compressed. That's true in the
        # limited case of project files.
        
        byte = xmlfile.getc()
        xmlfile.rewind()
        
        xmlfile       = Zlib::GzipReader.new( xmlfile ) if ( byte != '<'[ 0 ] )
        xmldoc        = REXML::Document.new( xmlfile.read() )
        @import.tasks, @import.new_categories = get_tasks_from_xml( xmldoc )

        if ( @import.tasks.nil? or @import.tasks.empty? )
          flash[ :error  ] = 'No usable tasks were found in that file'
        else
          flash[ :notice ] = 'Tasks read successfully. Please choose items to import.'
        end
        
      rescue => error
        
        # REXML errors can be huge, including a full backtrace. It can cause
        # session cookie overflow and we don't want the user to see it. Cut
        # the message off at the first newline.
        
        lines = error.message.split("\n")
        flash[ :error  ] = "Failed to read file: #{ lines[ 0 ] }"
      end

      render( { :action => :new } )
      flash.delete( :error  )
      flash.delete( :notice )
      
    else
      
      # No file was specified. If there are no tasks either, complain.
      
      tasks = params[ :import ][ :tasks ]
      
      if ( tasks.nil? )
        flash[ :error ] = "Please choose a file before using the 'Analyse' button."
        render( { :action => :new } )
        flash.delete( :error  )
        return
      end
      
      # Compile the form submission's task list into something that the
      # TaskImport object understands.
      #
      # Since we'll rebuild the tasks array inside @import, we can render the
      # 'new' view again and have the same task list presented to the user in
      # case of error.
      
      @import.tasks = []
      @import.new_categories = []
      to_import     = []
      
      # Due to the way the form is constructed, 'task' will be a 2-element
      # array where the first element contains a string version of the index
      # at which we should store the entry and the second element contains
      # the hash describing the task itself.
      
      tasks.each do | taskinfo |
        index  = taskinfo[ 0 ].to_i
        task   = taskinfo[ 1 ]
        struct = OpenStruct.new

        struct.uid = task[ :uid ]        
        struct.title    = task[ :title    ]
        struct.level    = task[ :level    ]
        struct.code     = task[ :code     ]
        struct.duration = task[ :duration ]
        struct.start = task[ :start ]
        struct.finish = task[ :finish ]
        struct.percentcomplete = task[ :percentcomplete ]
        struct.predecessors = task[ :predecessors ].split(', ')
        struct.category = task[ :category ]
        struct.assigned_to = task[ :assigned_to ]
        
        @import.tasks[ index ] = struct
        to_import[ index ] = struct if ( task[ :import ] == '1' )
      end
      
      to_import.compact!
      
      # The "import" button in the form causes token "import_selected" to be
      # set in the params hash. The "analyse" button causes nothing to be set.
      # If the user has clicked on the "analyse" button but we've reached this
      # point, then they didn't choose a new file yet *did* have a task list
      # available. That's strange, so raise an error.
      #
      # On the other hand, if the 'import' button *was* used but no tasks were
      # selected for error, raise a different error.
      
      if ( params[ :import ][ :import_selected ].nil? )
        flash[ :error ] = 'No new file was chosen for analysis. Please choose a file before using the "Analyse" button, or use the "Import" button to import tasks selected in the task list.'
      elsif ( to_import.empty? )
        flash[ :error ] = 'No tasks were selected for import. Please select at least one task and try again.'
      end
      
      # Get defaults to use for all tasks - sure there is a nicer ruby way, but this works
      #
      # Tracker
      default_tracker_name = Setting.plugin_redmine_loader['tracker']
      default_tracker = Tracker.find(:first, :conditions => [ "name = ?", default_tracker_name])
      default_tracker_id = default_tracker.id

      if ( default_tracker_id.nil? )
        flash[ :error ] = 'No valid default Tracker. Please ask your System Administrator to resolve this.'
      end
      
      # Bail out if we have errors to report.
      unless( flash[ :error ].nil? )
        render( { :action => :new } )
        flash.delete( :error  )
        return
      end
      
      # We're going to keep track of new issue ID's to make dependencies work later
      uidToIssueIdMap = {}

      # Right, good to go! Do the import.
      begin
        Issue.transaction do
          to_import.each do | source_issue |

            # Add the category entry if necessary
            category_entry = IssueCategory.find :first, :conditions => { :project_id => @project.id, :name => source_issue.category }

            if (category_entry.nil?)
              # Need to create it
              category_entry = IssueCategory.new do |i|
                i.name = source_issue.category
                i.project_id = @project.id
              end

              category_entry.save!
            end

            destination_issue          = Issue.new do |i|
              i.tracker_id = default_tracker_id
              i.category_id = category_entry.id
              i.subject    = source_issue.title.slice(0, 255) # Max length of this field is 255
              i.estimated_hours = source_issue.duration
              i.project_id = @project.id
              i.author_id = User.current.id
              i.lock_version = 0
              i.done_ratio = source_issue.percentcomplete
              i.description = source_issue.title
              i.start_date = source_issue.start
              i.due_date = source_issue.finish unless source_issue.finish.nil?
              i.due_date = (Date.parse(source_issue.start, false) + ((source_issue.duration.to_f/40.0)*7.0).to_i).to_s unless i.due_date != nil

              if ( source_issue.assigned_to != "" )
                i.assigned_to_id = source_issue.assigned_to
                i.status_id = IssueStatus.find_by_name("Assigned").id
              end
            end

            destination_issue.save!
            
            # Now that we know this issue's Redmine issue ID, save it off for later
            uidToIssueIdMap[ source_issue.uid ] = destination_issue.id
          end
          
          flash[ :notice ] = "#{ to_import.length } #{ to_import.length == 1 ? 'task' : 'tasks' } imported successfully."
        end
        
        # Handle all the dependencies being careful if the parent doesn't exist
        IssueRelation.transaction do
          to_import.each do | source_issue |
            source_issue.predecessors.each do | parent_uid |
              if ( uidToIssueIdMap.has_key?(parent_uid) )
                # Parent is being imported also.  Go ahead and add the association
                relation_record = IssueRelation.new do |i|
                  i.issue_from_id = uidToIssueIdMap[parent_uid]
                  i.issue_to_id = uidToIssueIdMap[source_issue.uid]
                  i.relation_type = 'precedes'
                end
                relation_record.save!
              end
            end
          end
        end
    
        redirect_to( "/projects/#{@project.identifier}/issues" )
        
        
      rescue => error
        flash[ :error ] = "Unable to import tasks: #{ error }"
        render( { :action => :new } )
        flash.delete( :error )
        
      end
    end
  end
  
  private
  
  # Is the current action permitted?

  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id])
  end
  
  # Obtain a task list from the given parsed XML data (a REXML document).
  
  def get_tasks_from_xml( doc )
    
    # Extract details of every task into a flat array
    tasks = []
    
    doc.each_element( 'Project/Tasks/Task' ) do | task |
      begin
        struct = OpenStruct.new
        struct.level  = task.get_elements( 'OutlineLevel' )[ 0 ].text.to_i
        struct.tid    = task.get_elements( 'ID'           )[ 0 ].text.to_i
        struct.uid    = task.get_elements( 'UID'          )[ 0 ].text.to_i
        struct.title  = task.get_elements( 'Name'         )[ 0 ].text.strip
        struct.start  = task.get_elements( 'Start'        )[ 0 ].text.split("T")[0]
        
        struct.finish  = task.get_elements( 'Finish'        )[ 0 ].text.split("T")[0] unless task.get_elements( 'Finish')[ 0 ].nil?
        struct.percentcomplete = task.get_elements( 'PercentComplete')[0].text.to_i

        # Handle dependencies
        struct.predecessors = []
        task.each_element( 'PredecessorLink' ) do | predecessor |
          begin
            struct.predecessors.push( predecessor.get_elements('PredecessorUID')[0].text.to_i )
          end
        end
          
        tasks.push( struct )
      rescue
        # Ignore errors; they tend to indicate malformed tasks, or at least,
        # XML file task entries that we do not understand.
      end
    end
    
    # Sort the array by ID. By sorting the array this way, the order
    # order will match the task order displayed to the user in the
    # project editor software which generated the XML file.
    
    tasks = tasks.sort_by { | task | task.tid }
    
    # Step through the sorted tasks. Each time we find one where the
    # *next* task has an outline level greater than the current task,
    # then the current task MUST be a summary. Record its name and
    # blank out the task from the array. Otherwise, use whatever
    # summary name was most recently found (if any) as a name prefix.

    all_categories = []
    category = ''
    
    tasks.each_index do | index |
      task      = tasks[ index     ]
      next_task = tasks[ index + 1 ]
      
      if ( next_task and next_task.level > task.level )
        category         = task.title.strip.gsub(/:$/, '') # Kill any trailing :'s which are common in some project files
        all_categories.push(category)   # Keep track of all categories so we know which ones might need to be added
        tasks[ index ] = nil
      else
        task.category = category
      end
    end

    # Remove any 'nil' items we created above
    tasks.compact!
    tasks = tasks.uniq
    
    # Now create a secondary array, where the UID of any given task is
    # the array index at which it can be found. This is just to make
    # looking up tasks by UID really easy, rather than faffing around
    # with "tasks.find { | task | task.uid = <whatever> }".
    
    uid_tasks = []
    
    tasks.each do | task |
      uid_tasks[ task.uid ] = task
    end
    
    # OK, now it's time to parse the assignments into some meaningful
    # array. These will become our redmine issues. Assignments
    # which relate to empty elements in "uid_tasks" or which have zero
    # work are associated with tasks which are either summaries or
    # milestones. Ignore both types.
    
    real_tasks = []
    
    doc.each_element( 'Project/Assignments/Assignment' ) do | as |
      task_uid = as.get_elements( 'TaskUID' )[ 0 ].text.to_i
      task = uid_tasks[ task_uid ] unless task_uid.nil?
      next if ( task.nil? )
      
      work = as.get_elements( 'Work' )[ 0 ].text
      
      # Parse the "Work" string: "PT<num>H<num>M<num>S", but with some
      # leniency to allow any data before or after the H/M/S stuff.
      hours = 0
      mins = 0
      secs = 0
      
      strs = work.scan(/.*?(\d+)H(\d+)M(\d+)S.*?/).flatten unless work.nil?
      hours, mins, secs = strs.map { | str | str.to_i } unless strs.nil?
      
      #next if ( hours == 0 and mins == 0 and secs == 0 )
      
      # Woohoo, real task!
      
      task.duration = ( ( ( hours * 3600 ) + ( mins * 60 ) + secs ) / 3600 ).prec_f
      
      real_tasks.push( task )
    end
    
    real_tasks = tasks if real_tasks.nil?
    real_tasks = real_tasks.uniq unless real_tasks.nil?
    all_categories = all_categories.uniq.sort

    return real_tasks, all_categories
  end
end
