define cassandra::instance inherits cassandra (
  $instance                     = $title,
  $baseline_settings            = $::cassandra::baseline_settings,
  $cassandra_2356_sleep_seconds = $::cassandra::cassandra_2356_sleep_seconds,
  $cassandra_9822               = $::cassandra::cassandra_9822,
  $cassandra_yaml_tmpl          = $::cassandra::cassandra_yaml_tmpl,
  $commitlog_directory          = $::cassandra::commitlog_directory,
  $commitlog_directory_mode     = $::cassandra::commitlog_directory_mode,
  Boolean $manage_config_file   = $::cassandra::manage_config_file,
  $config_file_mode             = $::cassandra::config_file_mode,
  $config_path                  = $::cassandra::config_path,
  $data_file_directories        = $::cassandra::data_file_directories,
  $data_file_directories_mode   = $::cassandra::data_file_directories_mode,
  $dc                           = $::cassandra::dc,
  $dc_suffix                    = $::cassandra::dc_suffix,
  $fail_on_non_supported_os     = $::cassandra::fail_on_non_supported_os,
  $hints_directory              = $::cassandra::hints_directory,
  $hints_directory_mode         = $::cassandra::hints_directory_mode,
  $prefer_local                 = $::cassandra::prefer_local,
  $rack                         = $::cassandra::rack,
  $rackdc_tmpl                  = $::cassandra::rackdc_tmpl,
  $saved_caches_directory       = $::cassandra::saved_caches_directory,
  $saved_caches_directory_mode  = $::cassandra::saved_caches_directory_mode,
  $service_enable               = $::cassandra::service_enable,
  $service_ensure               = $::cassandra::service_ensure,
  $service_refresh              = $::cassandra::service_refresh,
  $settings                     = $::cassandra::settings,
  $snitch_properties_file       = $::cassandra::snitch_properties_file,
  $systemctl                    = $::cassandra::systemctl,
) {

  $config_file = "${config_path}/cassandra.yaml"
  $dc_rack_properties_file = "${config_path}/${snitch_properties_file}"

  include cassandra

  case $::osfamily {
    'RedHat': {
      $config_file_require = Package['cassandra']
      $config_file_before  = []
      $config_path_require = Package['cassandra']
      $dc_rack_properties_file_require = Package['cassandra']
      $dc_rack_properties_file_before  = []
      $data_dir_require = Package['cassandra']
      $data_dir_before = []

      if $::operatingsystemmajrelease == '7' and $::cassandra::service_provider == 'init' {
        exec { "/sbin/chkconfig --add ${service_name}":
          unless  => "/sbin/chkconfig --list ${service_name}",
          require => Package['cassandra'],
          before  => Service[$instance],
        }
      }
    }
    'Debian': {
      $config_file_require = [ User['cassandra'], File[$config_path] ]
      $config_file_before  = Package['cassandra']
      $config_path_require = []
      $dc_rack_properties_file_require = [ User['cassandra'], File[$config_path] ]
      $dc_rack_properties_file_before  = Package['cassandra']
      $data_dir_require = File[$config_file]
      $data_dir_before = Package['cassandra']

      if $cassandra_9822 {
        file { "/etc/init.d/$title":
          source => 'puppet:///modules/cassandra/CASSANDRA-9822/cassandra',
          mode   => '0555',
          before => Package['cassandra'],
        }
      }
      # Sleep after package install and before service resource to prevent
      # possible duplicate processes arising from CASSANDRA-2356.
      exec { "CASSANDRA-2356 sleep $title":
        command     => "/bin/sleep ${cassandra_2356_sleep_seconds}",
        refreshonly => true,
        user        => 'root',
        subscribe   => Package['cassandra'],
        before      => Service[$title],
      }
      # End of CASSANDRA-2356 specific resources.
    }
    default: {
      $config_file_before  = [ Package['cassandra'] ]
      $config_file_require = []
      $config_path_require = []
      $dc_rack_properties_file_require = Package['cassandra']
      $dc_rack_properties_file_before  = []

      if $::cassandra::fail_on_non_supported_os {
        fail("OS family ${::osfamily} not supported")
      } else {
        warning("OS family ${::osfamily} not supported")
      }
    }
  }

  if $manage_config_file {
    file { $config_path:
      ensure  => directory,
      group   => 'cassandra',
      owner   => 'cassandra',
      mode    => '0755',
      require => $config_path_require,
    }
  }

  if $commitlog_directory {
    file { $commitlog_directory:
      ensure  => directory,
      owner   => 'cassandra',
      group   => 'cassandra',
      mode    => $commitlog_directory_mode,
      require => $data_dir_require,
      before  => $data_dir_before,
    }

    $commitlog_directory_settings = merge($settings,
      { 'commitlog_directory' => $commitlog_directory, })
  } else {
    $commitlog_directory_settings = $settings
  }

  if is_array($data_file_directories) {
    file { $data_file_directories:
      ensure  => directory,
      owner   => 'cassandra',
      group   => 'cassandra',
      mode    => $data_file_directories_mode,
      require => $data_dir_require,
      before  => $data_dir_before,
    }

    $data_file_directories_settings = merge($settings, {
      'data_file_directories' => $data_file_directories,
    })
  } else {
    $data_file_directories_settings = $settings
  }

  if $hints_directory {
    file { $hints_directory:
      ensure  => directory,
      owner   => 'cassandra',
      group   => 'cassandra',
      mode    => $hints_directory_mode,
      require => $data_dir_require,
      before  => $data_dir_before,
    }

    $hints_directory_settings = merge($settings,
      { 'hints_directory' => $hints_directory, })
  } else {
    $hints_directory_settings = $settings
  }

  if $saved_caches_directory {
    file { $saved_caches_directory:
      ensure  => directory,
      owner   => 'cassandra',
      group   => 'cassandra',
      mode    => $saved_caches_directory_mode,
      require => $data_dir_require,
      before  => $data_dir_before,
    }

    $saved_caches_directory_settings = merge($settings,
      { 'saved_caches_directory' => $saved_caches_directory, })
  } else {
    $saved_caches_directory_settings = $settings
  }

  $merged_settings = merge($baseline_settings, $settings,
    $commitlog_directory_settings,
    $data_file_directories_settings,
    $hints_directory_settings,
    $saved_caches_directory_settings)

  file { $config_file:
    ensure  => present,
    owner   => 'cassandra',
    group   => 'cassandra',
    content => template($cassandra_yaml_tmpl),
    mode    => $config_file_mode,
    require => $config_file_require,
    before  => $config_file_before,
  }

  file { $dc_rack_properties_file:
    ensure  => file,
    content => template($rackdc_tmpl),
    owner   => 'cassandra',
    group   => 'cassandra',
    mode    => '0644',
    require => $dc_rack_properties_file_require,
    before  => $dc_rack_properties_file_before,
  }

  if $service_refresh {
    service { $title:
      ensure    => $service_ensure,
      name      => $service_name,
      enable    => $service_enable,
      subscribe => [
        File[$config_file],
        File[$dc_rack_properties_file],
        Package['cassandra'],
      ],
    }
  } else {
    service { $title:
      ensure  => $service_ensure,
      name    => $service_name,
      enable  => $service_enable,
      require => [
        File[$config_file],
        File[$dc_rack_properties_file],
        Package['cassandra'],
      ],
    }
  }
}
