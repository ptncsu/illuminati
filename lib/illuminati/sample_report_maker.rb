require 'illuminati/flowcell_record'
require 'illuminati/tab_file_parser'
require 'illuminati/casava_output_parser'

module Illuminati
  #
  # Aggregates all the crap necessary to fill out the simplest of all csv files.
  # Responsible for generating string to create Sample_Report.csv from.
  #
  class SampleReportMaker
    DATA_NAMES = [:output, :lane, :name, :illumina, :custom, :read, :genome]

    #
    # Makes the SampleReport string. Not actually outputing it to file.
    # Depends on FlowcellRecord, TabFileParser, and HtmlParser for most of
    # the work required.
    #
    # Most of the data comes from the FlowcellRecord. Currently, the only value
    # missing is the number of reads. This is contained either in the Demultiplex_Stats.htm
    # file for regular lanes or TruSeq lanes and in the fastx_barcode_splitter output
    # for custom barcoded reads... Fun stuff.
    #
    def self.make flowcell
      @flowcell = flowcell
      @demultiplex_filename = File.join(@flowcell.paths.unaligned_stats_dir, "Demultiplex_Stats.htm")
      @sample_summary_filename = File.join(@flowcell.paths.aligned_stats_dir, "Sample_Summary.htm")

      sample_report = ["output", "lane", "sample name", "illumina index",
                       "custom barcode", "read", "reference"].join(",")
      sample_report += ","
      sample_report += ["total reads", "pass filter reads", "pass filter percent"].join(",")
      sample_report += ","
      sample_report += ["align percent", "type", "read length"].join(",")
      sample_report += "\n"

      @flowcell.each_sample_with_lane do |sample, lane|
        read_data = data_for sample
        read_data.each do |sample_read_data|
          sample_read_string = sample_read_data.join(",")
          sample_report += sample_read_string
          sample_report += "\n"
        end
      end
      sample_report
    end

    #
    # Returns all the data for a single sample.
    # Deals with paired_end data, custom barcodes,
    # Illumina indexed barcodes and non-multiplexed lanes.
    #
    def self.data_for sample
      all_read_data = []
      sample_datas = sample.sample_report_data

      sample_datas.each do |sample_data|
        data = DATA_NAMES.collect {|key| sample_data[key]}
        run_data = []
        run_data = data_from_custom_barcode sample
        if run_data.empty?
          run_data = data_from_casava sample, sample_data[:read]
        else
          # custom barcode doesn't have other info
        end

        data << run_data unless run_data.empty?
        data.flatten!
        all_read_data << data
      end
      all_read_data
    end


    #
    # Returns the number of reads count from the Demultiplex_Stats.htm
    # file for a particular sample.
    #
    # Return value is a string. nil is returned if count cannot be found.
    #
    def self.data_from_casava sample, read
      parser = CasavaOutputParser.new(@demultiplex_filename, @sample_summary_filename)
      casava_data = parser.data_for(sample, read)
      data = []
      if casava_data.empty?
        puts "ERROR: sample report maker cannot find demultiplex data for #{sample.id}"
      else
        count = casava_data["# Reads"]
        data << count.to_s
        percent = casava_data["% PF"]
        count_num = count.to_f
        percent_num = percent.to_f
        pass_filter_count = (count_num * (percent_num / 100.0)).round
        data << pass_filter_count.to_s
        data << percent

        percent_align = casava_data["% Align (PF)"]
        data << percent_align
        type = (casava_data["Analysis Type"] == "eland extended") ? "single" : "paired"
        data << type
        data << casava_data["Length"]
      end
      data
    end


    #
    # Returns count value from custom barcode output for a particular sample.
    # Return value is a string. nil is returned if count cannot be found or
    # if no custom barcodde output file is present.
    #
    def self.data_from_custom_barcode sample
      data = []
      barcode_data = barcode_data_for_sample sample
      if barcode_data
        count = barcode_data["Count"]
        data << count << "" << ""
        data << "" << "" << "" << ""
      end
      data
    end

    #
    # Returns the barcode data for a particular sample from
    # all possible barcode data. Used by custom barcode count finder.
    #
    def self.barcode_data_for_sample sample
      barcode_filename = @flowcell.paths.custom_barcode_path_out(sample.lane.to_i)
      if File.exists? barcode_filename
        tab_parser = TabFileParser.new
        barcode_data = tab_parser.parse(barcode_filename)
        barcode_data.each do |barcode_line|
          if barcode_line["Barcode"] == sample.custom_barcode
            return barcode_line
          end
        end
      end
      nil
    end
  end
end

