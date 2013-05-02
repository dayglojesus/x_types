#X_types

A collection of custom Puppet types and providers for Mac OS X.

##Version: 0.0.2

##Requirements

* Minimum OS: Mac OS X 10.5.8
* RubyCocoa 1.0.2 or greater if deploying on Mac OS X Lion or Mountain Lion
 
##Notes

At first glance, this module may appear to duplicate previous Puppet functionality (it does), 
but it is worth noting that X_types has the ability to create and manage resources in 
arbitrary dslocal nodes -- a concept specific to Mac OS X management. It also adds support 
for managing some functionality specific to Mac OS X.

##Examples

###Core Functionality

####Declare the x_types class

    class { 'x_types': safe => 'false' }

* Declaring the x_types class is not require, but it is recommended.
* The class takes a single parameter: $safe. This is a hook to prevent x_types from loading on incompatible machines.
* The default value of $safe is 'true'. To disable this check, send the parameter 'false'.

####Create a new user

    x_user { 'mrsighup':
      ensure        => 'present',
      dslocal_node  => 'Default',
      uid           => '401',
      shell         => '/bin/bash',
      gid           => '80',
      home          => '/private/var/itsop',
      comment       => 'Mr. Signal Hangup',
      password_sha1 => '000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000C19C9172142311D9A261F178262E096D3567E54A37E8C9BD0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
      password_sha512 => '2e1d496fddd1e229719ee11c059afd4a1a65cd337ac21606a7725d887ac9e7baba0cc1d9eebb5d8a9dbe6be098672cab43f535baf8269d9ef2ad68632fb482119f5bcb7c',
      password_sha512_pbkdf2 => { entropy => '35d37696749e6626d9b7a3c615caad00cdae5953d9daaee856d1fc65e7b488c45ea37ccdb9e2dab524938eeb1882907b065019c4f23c8c2d16e710fda86faf8a1c9445c7eea5628bf21ac8a9ed6f588a39feca8f4acb25d85ee25bf227abc24881e5c6dee3accc2e9744f1db228745f1b0696c79ea323c4e80e2fd8f604d43e0', 
        iterations => '30378', salt => '3bb9c079dae85d6441eb29aa77a3e291c33412def852f6767c2bb7afd672de95' },
    }

####Create a new dslocal node

    x_node { 'MCX':
      active => 'true',
      provider => 'dslocal',
      ensure => 'present'
    }

####Create a new computer in the designated node

    x_computer { "$::hostname":
      dslocal_node  => 'MCX',
      en_address    => "$::macaddress_en0",
      hardware_uuid => "$::sp_platform_uuid",
      ensure        => 'present',
      require       => X_node['MCX']
    }

####Create a new computer group and add the new computer record to it

    x_computergroup { 'SomePolicyGroup':
      dslocal_node  => 'MCX',
      members       =>["$::hostname"],
      gid           => '5000',
      ensure        => 'present',
      require       => X_computer["$::hostname"]
    }

####Import MCX policy on the target computer group

    x_policy { 'SomePolicyGroup':
      dslocal_node  => 'MCX',
      provider      => 'x_mcx',
      type          => 'computergroup',
      plist         => '/private/etc/policy/mcx/applesoftwareupdates.plist',
      autocratic    => 'false',
      ensure        => 'present',
    }

* Setting autocratic mode to 'true' expunges the previous mcx_settings from the target record prior to application.
* Setting this to 'false', performs a merge where the policy that Puppet applies always takes precedence.
* autocratic => 'true' is the default

###Special Providers

####Enable Apple Remote Desktop

    x_remotemanagement { 'ard_setup':
      users     => { 'myadmin' => '-1073741569' },
      dirgroups => 'ardadmin, ardinteract, ardmanage, ardreports',
      dirlogins => 'enable',
      menuextra => 'disable',
      ensure    => 'running',
    }

####Bind to an Active Directory

    if "$::fqdn" == "$::certname" {
      x_node { 'some.domain':
        active        => 'true',
        ensure        => 'present'
        provider      => 'activedirectory',
        active        => 'true',
        computerid    => 'some_machine',
        username      => 'some_user',
        password      => 'a_password',
        ou            => 'CN=Computers',
        domain        => 'some.domain',
        mobile        => 'disable',
        mobileconfirm => 'disable',
        localhome     => 'disable',
        useuncpath    => 'enable',
        protocol      => 'afp',
        shell         => '/bin/false',
        groups        => 'SOME_DOMAIN\some_group,SOME_DOMAIN\another_group',
        passinterval  => '0',
      }
    } else {
      $msg = "Our FQDN ($::fqdn) does not match our certname ($::certname). Aborting Puppet run..."
      notice($msg)
      notify { $msg: }
    }

* Unless we have an authoritative hostname, abort bind operation

####Enable ipfw and apply a set of rules

    x_firewall { 'ipfw':
      verbosity => '2',
      file      => '/private/etc/ipfw/ipfw_rules',
      require   => File['/private/etc/ipfw'],
    }

* Rules read from a text file in the following form
* rule_num action proto from range to range
* Example: 12308 allow ip from 192.168.0.0/16 to any

####Create a login or logout hooks

    x_hook { 'loguser_in':
      type     => 'login',
      priority => '0',
      ensure   => 'present',
      content  => "
        #!/bin/bash
        USER_NAME=\${1}
        USER_UID=\${2}
        USER_GID=\${3}
        /usr/bin/syslog -s -r $syslog_server -l Info \"Login: \${USER_NAME}, uid=\${USER_UID}, gid=\${USER_GID}\"
        exit 0
      "
    }

* Allows you to define two types: login or logout
* Allows you to set a precedence for each script per type
* Scripts that share a precedence will be executed alphabetically
* Script content defined inline or as a file on disk

###Custom Facts

* filevault_enabled: boolean showing encryption status of the root volume
* rubycocoa_version: returns authoritative RubyCocoa version
* mac_console_users: adds 3 new custom facts
  * mac_console_users_names: names of users who have console sessions
  * mac_console_users_current: name of the user with current session
  * mac_console_users_total: number of user sessions

##Known Issues

* Using commands like: `puppet resource x_user blah` doesn't work for any types except x_user
* x_group provider is missing (unimplemented)
* x_mcx provider will continually re-apply policy under certain conditions (see comments in x_mcx.rb and x_policy.rb)
* x_profile provider for x_policy type still unimplemented
* x_firewall: alf provider unimplemented