define cassandra::instance inherits cassandra (
  String $service_name = $::cassandra::service_name,
  Boolean $manage_config_file = $::cassandra::manage_config_file,
  String $config_path = $::cassandra::config_path,
  String $snitch_properties_file = $::cassandra::snitch_properties_file,
  String $commitlog_directory = $::cassandra::commitlog_directory,
  String $commitlog_directory_mode = $::cassandra::commitlog_directory_mode,
  Boolean $cassandra_9822 = $::cassandra::cassandra_9822,
  String $cassandra_2356_sleep_seconds = $::cassandra::cassandra_2356_sleep_seconds,
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
          before  => Service['cassandra'],
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
        file { '/etc/init.d/cassandra':
          source => 'puppet:///modules/cassandra/CASSANDRA-9822/cassandra',
          mode   => '0555',
          before => Package['cassandra'],
        }
      }
      # Sleep after package install and before service resource to prevent
      # possible duplicate processes arising from CASSANDRA-2356.
      exec { 'CASSANDRA-2356 sleep':
        command     => "/bin/sleep ${cassandra_2356_sleep_seconds}",
        refreshonly => true,
        user        => 'root',
        subscribe   => Package['cassandra'],
        before      => Service['cassandra'],
      }

      group { 'cassandra':
        ensure => present,
      }

      $user = 'cassandra'

      user { $user:
        ensure     => present,
        comment    => 'Cassandra database,,,',
        gid        => 'cassandra',
        home       => '/var/lib/cassandra',
        shell      => '/bin/false',
        managehome => true,
        require    => Group['cassandra'],
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

  if $package_ensure != 'absent' and $package_ensure != 'purged' {
    if $service_refresh {
      service { 'cassandra':
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
      service { 'cassandra':
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
}
