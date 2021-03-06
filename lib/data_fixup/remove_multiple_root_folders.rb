module DataFixup::RemoveMultipleRootFolders
  def self.run(opts = {})

    limit = opts[:limit] || 1000

    while (folders = Folder.find(
      :all, :conditions => ["workflow_state != ? AND parent_folder_id IS NULL", 'deleted'],
      :select => "context_id, context_type", :having => "count(*) > 1", :group => "context_id, context_type", :limit => limit
      )
    ).any? do

      context_types = folders.map(&:context_type).uniq

      context_types.each do |context_type|

        if context_type == "Course"
          root_folder_name = Folder::ROOT_FOLDER_NAME
        elsif context_type == "User"
          root_folder_name = Folder::MY_FILES_FOLDER_NAME
        else
          root_folder_name = "files"
        end

        context_ids = folders.select{|f| f.context_type == context_type}.map(&:context_id)

        root_folders = Folder.find(:all, :conditions => [
          "context_type = ? AND context_id IN (?) AND workflow_state != ? AND parent_folder_id IS NULL",
          context_type, context_ids, 'deleted'
        ])

        context_ids.each do |context_id|

          context_root_folders = root_folders.select{|folder| folder.context_id == context_id}

          main_root_folder = context_root_folders.select{|folder|
            folder.name == root_folder_name
          }.sort{|f1, f2|
            f2.attachments.count + f2.sub_folders.count <=> f1.attachments.count + f1.sub_folders.count
          }.first

          if main_root_folder.nil?
            main_root_folder = Folder.new(
                :name => root_folder_name, :full_name => root_folder_name, :workflow_state => "visible")
            main_root_folder.context_type = context_type
            main_root_folder.context_id = context_id
            main_root_folder.save!
            context_root_folders << main_root_folder
          end

          if context_root_folders.count > 1
            context_root_folders.each do |folder|
              unless folder.id == main_root_folder.id
                Folder.transaction do
                  if folder.attachments.count > 0 || folder.sub_folders.count > 0
                    Folder.update_all({:parent_folder_id => main_root_folder.id}, {:id => folder.id})
                  else
                    Folder.update_all({:workflow_state => 'deleted'}, {:id => folder.id})
                  end
                end
              end
            end
          end

        end

      end
    end

  end
end