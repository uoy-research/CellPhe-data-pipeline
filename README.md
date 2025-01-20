# CellPhe Data Pipeline

Runs a dataset (defined as a collection of tiffs) through the full CellPhe pipeline including:

  - Segmentation
  - Tracking
  - Frame feature extraction
  - Time-series feature extraction

This is run using `Nextflow` which provides several useful features:

  - Submits jobs to Slurm without having to write any submission scripts
  - Can resume failed pipelines from the previous succesfully completed step
  - Can automatically send emails upon completion/failure

Full instructions will be made available soon.

# Data transfer diagram

TODO

# Running the Pipeline

## Prerequisites

  1. Ensuring access to `research0`
  2. Ensuring access to `Viking`
  3. Adding public/private key authentication to Viking

### Ensuring access to `research0`

`research0` is the name of a powerful Linux computer that resides on Campus that can be used for research purposes, typically executing long-running programs on it to free up your personal computer or to access licenced software.
It is used for the data pipeline as it is on the fast campus connection to the Viking service and using it frees up your laptop while the pipeline is executing.

All members of the University should be able to access it **provided you are connected to Eduroam or are on the [VPN](https://www.york.ac.uk/it-services/tools/vpn/)**.
If you are on Windows open up PowerShell (NB: I highly recommend changing the background to black), Mac users can use the Terminal, and run `ssh <username>@research0`.
As shown below, this should ask for your password and then display a welcome message. 

![Connecting to research0](docs/research0_access.png)

If this doesn't work, follow the [documentation on the Wiki](https://uoy.atlassian.net/wiki/spaces/RCS/pages/39158543/Accessing+the+Servers).

### Ensuring access to Viking

Unlike `research0`, access to Viking is given out upon request rather than automatically.
Ensure you have applied via [this form](https://docs.google.com/forms/d/e/1FAIpQLSfXkL10ypU6EQCBB2jS5oDwTpRMo77ppl7dvdbLnXm5zrKR7Q/viewform), with the Project Code `biol-imaging-2024`.
We don't need access to any restricted licenced software.

Once this has been granted, you can SSH into Viking in the same way as `research0`.

![Connecting to Viking](docs/viking_access.png)

### Adding public/private key authentication to Viking

The final step of preparation is to facilitate password-less SSH connection from `research0` to `Viking` so that the entire pipeline can be run without user input prompting for your password.
This is an alternative form of authentication to username & password which creates a pair of two 'keys', a public and a private.
The private one is associated with a specific machine (in this instance `research0`) and the public one is distributed to anywhere you wish to connect to (in this instance Viking, but it can also be used to authenticate to GitHub for example).

Run the following instruction to create the pair, accepting the defaults for the 3 options (location, passphrase, passphrase confirmation).

`ssh-keygen -t ed25519 -C "research0"`

The final step is to place the public key onto Viking so it can authenticate you.

Run `nano ~/.ssh/id_ed25519.pub` to open the key in the Nano text editor. 
Highlight the text with the cursor and right click to copy it, then exit Nano with Ctrl-X

Now SSH into Viking and open run the following command to open the Authorized Keys file, which is where the SSH command looks at an attempted login to see if the connecting machine has an SSH key registered.

`nano ~/.ssh/authorized_keys`

By default there is one already there, the "Flight HPC Cluster Key", so press the down arrow key to move to a new line and then right click to paste your `research0` key.
Save this with Ctrl-O then Enter, then exit Nano with Ctrl-X.
If you now disconnect from Viking (Ctrl-D) and try to reconnect, it should login you in using your SSH keys and not ask for your password.
If this doesn't work, try again or ask for help in Slack.

## Running

TODO instructions on getting Google Drive ID, pattern, and desired output name
