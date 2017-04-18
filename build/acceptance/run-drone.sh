#!/usr/bin/env bash

# @copyright Copyright (c) 2017, Daniel Calviño Sánchez (danxuliu@gmail.com)
#
# @license GNU AGPL version 3 or any later version
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Helper script to run the acceptance tests, which test a running Nextcloud
# instance from the point of view of a real user, in a Drone step.
#
# The acceptance tests are written in Behat so, besides running the tests, this
# script installs Behat, its dependencies, and some related packages in the
# "vendor" subdirectory of the acceptance tests. The acceptance tests expect
# that the last commit in the Git repository provides the default state of the
# Nextcloud server, so the script installs the Nextcloud server and saves a
# snapshot of the whole grandparent directory (no .gitignore file is used) in
# the Git repository. Finally, the acceptance tests also use the Selenium server
# to control a web browser, so this script waits for the Selenium server
# (provided in its own Drone service) to be ready before running the tests.

# Exit immediately on errors.
set -o errexit

# Ensure working directory is script directory, as some actions (like installing
# Behat through Composer or running Behat) expect that.
cd "$(dirname $0)"

SCENARIO_TO_RUN=$1

composer install

# Although Behat documentation states that using the BEHAT_PARAMS environment
# variable "You can set any value for any option that is available in a
# behat.yml file" this is currently not true for the constructor parameters of
# contexts (see https://github.com/Behat/Behat/issues/983). Thus, the default
# "behat.yml" configuration file has to be adjusted to provide the appropriate
# parameters for NextcloudTestServerContext.
ORIGINAL="\
        - NextcloudTestServerContext"
REPLACEMENT="\
        - NextcloudTestServerContext:\n\
            nextcloudTestServerHelper: NextcloudTestServerDroneHelper\n\
            nextcloudTestServerHelperParameters:"
sed "s/$ORIGINAL/$REPLACEMENT/" config/behat.yml > config/behat-drone.yml

cd ../../

echo "Installing and configuring Nextcloud server"
build/acceptance/installAndConfigureServer.sh

echo "Saving the default state so acceptance tests can reset to it"
find . -name ".gitignore" -exec rm --force {} \;
git add --all && echo 'Default state' | git -c user.name='John Doe' -c user.email='john@doe.org' commit --quiet --file=-

cd build/acceptance

# The Selenium server should be ready by now, as Composer typically takes way
# longer to execute than its startup (which is done in parallel in a Drone
# service), but just in case.
echo "Waiting for Selenium"
timeout 60s bash -c "while ! curl 127.0.0.1:4444 >/dev/null 2>&1; do sleep 1; done"

vendor/bin/behat --config=config/behat-drone.yml $SCENARIO_TO_RUN
