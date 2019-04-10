__MAKE_DEPLOY_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

include $(__MAKE_DEPLOY_DIR)/lib/host.mk


DEPLOY_SUPERUSER ?= root
DEPLOY_USER ?= $(PACKAGE)
DEPLOY_SUDO ?= 0

DEPLOY_ID ?= ~/.ssh/id_rsa.pub
DEPLOY_KEY ?= $(shell cat $(DEPLOY_ID))
DEPLOY_KEY_DATA ?= $(shell cat $(DEPLOY_ID) | awk '{print $$2}')

# If it's not already set, dynamically determine the URL of the revision
# control system repository.
DEPLOY_REPO ?= $(shell git remote -v show -n origin | awk '/Fetch/{ print $$3 }')

# Assign a release number to this deployment.  This release is assigned by the
# deploy system, and is distinct from the version of the application and the
# revision of source files under version control.
#
# An application may alter its configuration based on the system it is being
# installed onto.  External events, such as a hardware or software upgrade, may
# be cause to reinstall the the application.  The reinstallation may have
# different parameters, based on changes to the system, even while the
# application itself remains unchanged.
#
# Furthermore, configuration parameters may need to be changed independent of
# changes application's source code.  Such configuration changes may be cause to
# redeploy the application.
#
# For these reasons, a unique release number is assigned.  Further rationale
# can be found in the [build, release, run][1] factor of The Twelve-Factor App.
#
# [1]: https://12factor.net/build-release-run
DEPLOY_RELID = $(shell date -u +%Y%m%d%H%M%S)

deploy_rootdir ?= $$HOME/app
deploy_relrootdir ?= $(deploy_rootdir)/rel
deploy_reldir ?= $(deploy_relrootdir)/$(DEPLOY_RELID)
deploy_srcdir ?= $(deploy_rootdir)/src



# The following list of commands is execeuted on a remote machine when deploying
# the application.
#
#   - Invoke the [standard targets][1] (`make` and `make install`) for compiling
#     and installing the application.
#   - Create a symbolic link to the current release.
#
# If the user is permitted to execute commands as the superuser, `make install`
# will be executed with those privileges.  This allows the application to be
# installed to a system-wide location.  However, wherever possible, it is
# [recommended][2] to deploy and run the application as a separate user, in
# order to protect against adverse consequences of a security breach or
# accidental misbehavior.
#
# The `current` symbolic link provides a canonical path to refer to the current
# deployed release.  Using this path is preferred in external configuration
# files, and obviates the need to update most configuration on each deployment.
# The symbolic link also allows for easy rollback to a previous release, in the
# event that a new deployment encounters issues.
#
# This `current` symlink structure is inspired by the [directory structure][3]
# of installed Snap app packages as well as the [anatomy][4] of Mac OS X
# framework bundles.  It is also similar to the [structure][5] used by
# Capistrano, another deployment tool, with the exception that it is the symlink
# does not reside in the parent directory.
#
# [1]: https://www.gnu.org/prep/standards/html_node/Standard-Targets.html
# [2]: https://unix.stackexchange.com/questions/29159/why-is-it-recommended-to-create-a-group-and-user-for-some-applications
# [3]: https://docs.snapcraft.io/the-system-snap-directory/2817
# [4]: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html
# [5]: https://capistranorb.com/documentation/getting-started/structure/
REMOTE_DEPLOY_COMMAND =\
set -e; \
cd $(deploy_srcdir); \
make prefix=$(deploy_reldir); \
if sudo -v 2> /dev/null; then \
  sudo make prefix=$(deploy_reldir) install; \
  if [ -d $(deploy_relrootdir) ]; then \
    sudo ln -sfn $(DEPLOY_RELID) $(deploy_relrootdir)/current; \
  fi; \
else \
  make prefix=$(deploy_reldir) install; \
  if [ -d $(deploy_relrootdir) ]; then \
    ln -sfn $(DEPLOY_RELID) $(deploy_relrootdir)/current; \
  fi; \
fi;

# TODO: After deploy, remove old releases beyond a configurable threshold.
# TODO: implement a rollback target

# Deploy on remote host.
#
# This target is invoked locally to deploy the application to a remote machine.
# After updating the application's source code, `make` and `make install` will
# be invoked on the remote machine.  The application must supply a Makefile with
# these targets, which should compile and install the application.
deploy@%:
	@$(MAKE) sync@$*
	@echo "Deploying to $(subst !,:,$*)..."
	ssh $(SSHFLAGS) $(call sshhost,$(subst !,:,$*),$(DEPLOY_USER)) '$(REMOTE_DEPLOY_COMMAND)'

# Deploy on all remote hosts.
#
# NOTE: Any colon (:), used to denote a port, in the value of the `HOSTS`
#       variable is substitued with an exclamation mark (!).  This is a
#       workaround to satisfy make's pattern matching.  The inverse operation is
#       performed when executing the recipe.
.PHONY: deploy
deploy: $(patsubst %, deploy@%, $(subst :,!,$(HOSTS)))



# The following list of commands are execeuted on a remote machine when
# synchronizing the application's source code.
#
#   - Exit immediately if any command returns a non-zero status, indicating an
#     error.
#   - If the source directory does not exist, check out a working copy of the
#     remote repository to that directory.
#   - Otherwise, if the source directory does exist, update the working copy
#     with any changes from the remote repository.
#   - The working copy is then reset to match the state of the remote
#     repository, including removing any files that are not under revision
#     control.  The effect of this operation should be equivalent to invoking
#     `make distclean`, for projects that provide [standard targets][1] for
#     Makefiles described by the GNU coding standards.
#
# [1]: https://www.gnu.org/prep/standards/html_node/Standard-Targets.html
REMOTE_SYNC_COMMAND =\
set -e; \
if [ ! -d $(deploy_srcdir) ]; then \
  git clone --depth=1 $(DEPLOY_REPO) $(deploy_srcdir); \
else \
  cd $(deploy_srcdir); \
  git fetch --depth=1 origin; \
  git reset --hard origin/master; \
  git clean -fdx; \
fi;

# Sync on remote host.
#
# This target is invoked locally to synchronize the application's source code on
# a remote machine.
sync@%:
	@echo "Syncing $(subst !,:,$*)..."
	ssh $(SSHFLAGS) $(call sshhost,$(subst !,:,$*),$(DEPLOY_USER)) '$(REMOTE_SYNC_COMMAND)'

# Sync to all remote hosts.
#
# NOTE: Any colon (:), used to denote a port, in the value of the `HOSTS`
#       variable is substitued with an exclamation mark (!).  This is a
#       workaround to satisfy make's pattern matching.  The inverse operation is
#       performed when executing the recipe.
.PHONY: sync
sync: $(patsubst %, sync@%, $(subst :,!,$(HOSTS)))



# The following list of commands is execeuted when preparing a remote machine.
#
#   - Exit immediately if any command returns a non-zero status, indicating an
#     error.
#   - Install `make` if it is not already installed.  `make` is required by the
#     deploy system in order to compile and install an application.
#   - If the user the application will run as does not exist, create a new user
#     as a system account (as indicated by the -r option), and...
#   - If the user the application will run as should be permitted to execute
#     commands as the superuser, grant them sudo privileges, otherwise...
#   - Enable user lingering so that the user can run long-running services when
#     not logged in.
#
# Granting sudo privledges to the user (by setting `DEPLOY_SUDO`) is NOT
# recommended.  Instead, the application should be deployed and run as a
# separate user, in order to protect against adverse consequences of a security
# breach or accidental misbehavior.
REMOTE_PREPARE_COMMAND =\
set -e; \
if ! type make &> /dev/null; then \
  sudo apt-get install make; \
fi; \
if ! id -u $(1) &> /dev/null; then \
  sudo useradd -r -m $(1); \
  if [ "$(2)" -eq "1" ]; then \
    sudo usermod -aG sudo $(1); \
  else \
    if type loginctl &> /dev/null; then \
      sudo loginctl enable-linger $(1); \
    fi; \
  fi; \
fi;

# Prepare remote host.
#
# This target is invoked locally to prepare a remote machine for deploying the
# application.
#
# When preparing the machine, the necessary packages for the deploy system will
# be installed.  Naturally, the only dependency is `make`, as this is a
# make-based deploy system.
#
# A separate user account will be created, which will be used to run the
# application.  This is a [best practice][1] to mitigate the consequences of a
# vulnerability, which is an especially crucial concern as the application will
# expose itself as a service via the network.
#
# These commands are executed as the superuser on the remote machine, in order
# to obtain the necessary privileges to complete successfully.
#
# [1]: https://www.nixu.com/blog/things-security-auditors-will-nag-about-part-2-lets-run-root
prepare@%:
	@echo "Preparing $(subst !,:,$*)..."
	ssh $(SSHFLAGS) $(call sshhost,$(subst !,:,$*),$(DEPLOY_SUPERUSER),1) '$(call REMOTE_PREPARE_COMMAND,$(call user,$(subst !,:,$*),$(DEPLOY_USER)),$(DEPLOY_SUDO))'
	@$(MAKE) copy-id@$*
	@$(MAKE) predeploy@$*

# Prepare all remote hosts.
#
# NOTE: Any colon (:), used to denote a port, in the value of the `HOSTS`
#       variable is substitued with an exclamation mark (!).  This is a
#       workaround to satisfy make's pattern matching.  The inverse operation is
#       performed when executing the recipe.
.PHONY: prepare
prepare: $(patsubst %, prepare@%, $(subst :,!,$(HOSTS)))



# The following list of commands is execeuted when copying an SSH identity to a
# remote host.
#
#   - Exit immediately if any command returns a non-zero status, indicating an
#     error.
#   - Create the .ssh directory, as the user which will run the application.
#   - Remove any access to group and other users.
#   - Create the authorized_keys file, as the user which will run the
#     application.
#   - Remove any access to group and other users.
#   - Add the key as an authorized key, if it is not already authorized.
REMOTE_COPY_ID_COMMAND =\
set -e; \
sudo -u $(1) mkdir -p ~$(1)/.ssh; \
sudo chmod go= ~$(1)/.ssh; \
sudo -u $(1) touch ~$(1)/.ssh/authorized_keys; \
sudo chmod go= ~$(1)/.ssh/authorized_keys; \
if ! sudo grep [[:blank:]]$(DEPLOY_KEY_DATA)[[:blank:]] ~$(1)/.ssh/authorized_keys &> /dev/null; then \
  sudo echo $(DEPLOY_KEY) >> ~$(1)/.ssh/authorized_keys; \
fi;

# Copy SSH key to remote host.
#
# This target uses a local SSH key to authorize logins on a remote machine.
#
# The SSH key (also known as an identity) is added as an authorized key for the
# user account which is used to deploy and run the application.  This is done by
# appending them to ~/.ssh/authorized_keys (creating the file, and directory, if
# necessary).
#
# This target is named after [ssh-copy-id][1], which performs a similar
# operation by adding authorized keys to a remote machine where authentication
# first occurs by using a password.  In contrast, this target logs in as the
# superuser, preferrably using public key authentication, and adds authorized
# keys for the user account which is used to run the application.
#
# These commands are executed as the superuser on the remote machine, in order
# to obtain the necessary privileges to complete successfully.
#
# [1]: https://linux.die.net/man/1/ssh-copy-id
copy-id@%:
	@echo "Copying ID to $(subst !,:,$*)..."
	ssh $(SSHFLAGS) $(call sshhost,$(subst !,:,$*),$(DEPLOY_SUPERUSER),1) '$(call REMOTE_COPY_ID_COMMAND,$(call user,$(subst !,:,$*),$(DEPLOY_USER)))'

# Copy SSH key to all remote hosts.
#
# NOTE: Any colon (:), used to denote a port, in the value of the `HOSTS`
#       variable is substitued with an exclamation mark (!).  This is a
#       workaround to satisfy make's pattern matching.  The inverse operation is
#       performed when executing the recipe.
.PHONY: copy-id
copy-id: $(patsubst %, copy-id@%, $(subst :,!,$(HOSTS)))



# The following list of commands is execeuted on a remote machine when
# predeploying the application.
#
#   - Invoke the target for installing system-wide dependencies.
REMOTE_PREDEPLOY_COMMAND =\
set -e; \
cd $(subst $$HOME,~$(1),$(deploy_srcdir)); \
sudo make preinstall;

# Predeploy on remote host.
#
# This target is invoked locally to prepare a remote machine for running the
# application by invoking `make preinstall`.  The application must supply a
# Makefile with this target, which should install system-wide dependencies.
#
# In order to keep the application [erosion-resistant][1], it is recommended to
# keep system-wide dependencies to a minimum and prefer [dependency
# isolation][2].  Dependencies which are commonly needed, and suitable for
# system-wide installation, include the language runtime and dependency manager.
#
# [1]: https://blog.heroku.com/the_new_heroku_4_erosion_resistance_explicit_contracts
# [2]: https://12factor.net/dependencies
predeploy@%:
	@$(MAKE) sync@$*
	@echo "Predeploying $(subst !,:,$*)..."
	ssh $(SSHFLAGS) $(call sshhost,$(subst !,:,$*),$(DEPLOY_SUPERUSER),1) '$(call REMOTE_PREDEPLOY_COMMAND,$(call user,$(subst !,:,$*),$(DEPLOY_USER)))'

# Predeploy on all remote hosts.
#
# NOTE: Any colon (:), used to denote a port, in the value of the `HOSTS`
#       variable is substitued with an exclamation mark (!).  This is a
#       workaround to satisfy make's pattern matching.  The inverse operation is
#       performed when executing the recipe.
.PHONY: predeploy
predeploy: $(patsubst %, predeploy@%, $(subst :,!,$(HOSTS)))
