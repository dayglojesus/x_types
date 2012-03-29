# Class: x_types
#
# This module manages x_types
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage:
#
# [Remember: No empty lines between comments and class definition]
class x_types( $safe = 'true' ) {

  if $safe == 'true' {
    case $::macosx_productversion_major {
      "10.7": {
        if "$::rubycocoa_version" < "1.0.2" {
          fail("X_types module on Mac OS X Lion requires RubyCocoa 1.0.2 or better. See README for more details.")
        }
      }
    }
  } elsif $safe == 'false' {
    $msg = "Saftey check disabled. Loading X_types without checking RubyCocoa version."
    notice($msg)
    notify { $msg: }
  } else {
    fail("Invalid parameter: $safe")
  }
  
}