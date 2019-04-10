# host macros
#
# CREDIT: https://stackoverflow.com/questions/8540485/how-do-i-split-a-string-in-make/8540718



# Is a string containing the host, that is the hostname, a ':', and the port.
#
# Usage:
#   $(call host,example.com) # example.com
#   $(call host,example.com:22) # example.com:22
#   $(call host,user@example.com:22) # example.com:22
#
# Parameters:
#   $(1) URL to parse, in the form user@host:port
host = $(lastword $(subst @, ,$(1)))

# Is a string containing the hostname.
#
# Usage:
#   $(call host,example.com) # example.com
#   $(call host,example.com:22) # example.com
#   $(call host,user@example.com:22) # example.com
#
# Parameters:
#   $(1) URL to parse, in the form user@host:port
hostname = $(firstword $(subst :, ,$(call host,$(1))))

# Is a string containing the port number.
#
# Usage:
#   $(call host,example.com:22) # 22
#
# Parameters:
#   $(1) URL to parse, in the form user@host:port
port = $(or $(word 2, $(subst :, ,$(call host,$(1)))),$(2))

# Is a string containing the username.
#
# Usage:
#   $(call host,user@example.com) # user
#
# Parameters:
#   $(1) URL to parse, in the form user@host:port
user = $(if $(3),$(2),$(if $(findstring @,$(1)),$(firstword $(subst @, ,$(1))),$(2)))


sshhost = $(if $(call port,$(1)),-p $(call port,$(1)) )$(if $(call user,$(1),$(2),$(3)),$(call user,$(1),$(2),$(3))@)$(call hostname,$(1))
scphost = $(if $(call port,$(1)),-P $(call port,$(1)) )$(if $(call user,$(1),$(2),$(3)),$(call user,$(1),$(2),$(3))@)$(call hostname,$(1))
