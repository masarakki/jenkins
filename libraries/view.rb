#
# Cookbook Name:: jenkins
# HWRP:: group
#
# Copyright 2013-2014, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative '_helper'
require_relative '_params_validate'

class Chef
  class Resource::JenkinsView < Resource::LWRPBase
    # Chef attributes
    identity_attr :name
    provides :jenkins_view

    # Set the resource name
    self.resource_name = :jenkins_view

    # Actions
    actions :create, :delete, :append
    default_action :create

    # Attributes
    attribute :name,
      kind_of: String
    attribute :job,
      kind_of: String

    attr_writer :exists

    #
    # Determine if the job exists on the master. This value is set by the
    # provider when the current resource is loaded.
    #
    # @return [Boolean]
    #
    def exists?
      !!@exists
    end
  end
end

class Chef
  class Provider::JenkinsView < Provider::LWRPBase
    class ViewDoesNotExist < StandardError
      def initialize(group, action)
        super <<-EOH
The Jenkins view `#{view}' does not exist. In order to #{action} `#{view}', that view must first exist on the Jenkins master!
EOH
      end
    end

    require 'rexml/document'
    include Jenkins::Helper

    def load_current_resource
      @current_resource ||= Resource::JenkinsView.new(new_resource.name)
      @current_resource.name(new_resource.name)
      @current_resource.exists = !!current_view

      @current_resource
    end

    #
    # This provider supports why-run mode.
    #
    def whyrun_supported?
      true
    end

    #
    # Idempotently create a new Jenkins job with the current resource's name
    # and configuration file. If the job already exists, no action will be
    # taken. If the job does not exist, one will be created from the given
    # `config` XML file using the Jenkins CLI.
    #
    # This method also ensures the given configuration file matches the one
    # rendered on the Jenkins master. If the configuration file does not match,
    # a new one is rendered.
    #
    # Requirements:
    #   - `config` parameter
    #
    action(:create) do
      if current_resource.exists?
        Chef::Log.debug("#{new_resource} exists - skipping")
      else
        converge_by("Create #{new_resource}") do
          executor.execute!('create-view', escape(new_resource.name), input: xml)
        end
      end

      if correct_config?
        Chef::Log.debug("#{new_resource} config up to date - skipping")
      else
        converge_by("Update #{new_resource} config") do
          executor.execute!('update-view', escape(new_resource.name), input: xml)
        end
      end
    end

    #
    # Idempotently delete a Jenkins job with the current resource's name. If
    # the job does not exist, no action will be taken. If the job does exist,
    # it will be deleted using the Jenkins CLI.
    #
    action(:delete) do
      if current_resource.exists?
        converge_by("Delete #{new_resource}") do
          executor.execute!('delete-view', escape(new_resource.name))
        end
      else
        Chef::Log.debug("#{new_resource} does not exist - skipping")
      end
    end

    action(:append) do
      converge_by("Append #{new_resource.job} to #{new_resource.name}") do
        executor.execute!('add-job-to-view', new_resource.name, new_resource.job)
      end
    end

    private

    #
    # The job in the current, in XML format.
    #
    # @return [nil, Hash]
    #   nil if the job does not exist, or a hash of important information if
    #   it does
    #
    def current_view
      return @current_view if @current_view

      Chef::Log.debug "Load #{new_resource} view information"

      response = executor.execute('get-view', escape(new_resource.name))
      return nil if response.nil? || response =~ /No viwe/

      Chef::Log.debug "Parse #{new_resource} as XML"
      xml = REXML::Document.new(response)

      @current_view = {
        xml:     xml,
        raw:     response,
      }
      @current_view
    end

    #
    # Helper method for determining if the given JSON is in sync with the
    # current configuration on the Jenkins master.
    #
    # We have to create REXML objects and then remove any whitespace because
    # XML is evil and sometimes sucks at the simplest things, like comparing
    # itself.
    #
    # @return [Boolean]
    #
    def correct_config?
      current = StringIO.new
      wanted  = StringIO.new

      current_view[:xml].write(current, 2)
      REXML::Document.new(xml).write(wanted, 2)

      current.string == wanted.string
    end

    def xml
      @config_xml ||= <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hudson.model.ListView>
  <name>#{new_resource.name}</name>
  <filterExecutors>false</filterExecutors>
  <filterQueue>false</filterQueue>
  <properties class="hudson.model.View$PropertyList"/>
  <jobNames>
    <comparator class="hudson.util.CaseInsensitiveComparator"/>
  </jobNames>
  <jobFilters/>
  <columns>
    <hudson.views.StatusColumn/>
    <hudson.views.WeatherColumn/>
    <hudson.views.JobColumn/>
    <hudson.views.LastSuccessColumn/>
    <hudson.views.LastFailureColumn/>
    <hudson.views.LastDurationColumn/>
    <hudson.views.BuildButtonColumn/>
  </columns>
</hudson.model.ListView>
EOF
    end
  end
end

Chef::Platform.set(
  resource: :jenkins_view,
  provider: Chef::Provider::JenkinsView
)
