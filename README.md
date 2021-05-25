# Agentless Salt for Windows

> **NOTE:** This is an _archived_ repository! Agentless Salt for Windows was originally created for SaltStack Enterprise customers and has not been updated since 2017. This repository is being open sourced, but the project is not supported at this time. Feel free to fork and make use of the code in accordance with the `LICENSE` file.

## About

The Agentless Windows Module can run any Salt SSH command on a target Windows server or desktop, such as the following:

```
salt-ssh testwin disk.usage
```

## Requirements

### Target Windows systems

- English version of Windows
- Windows versions:
  - Windows 7
  - Windows 8.1
  - Windows 10
  - Windows Server 2008 R2
  - Windows Server 2012 R2
  - Windows Server 2016
- Powershell 3.0 or later
- WinRM must be configured and running

Winrm must be set up and configured on the Windows machine to run https on port
5986. The Windows firewall also must be set up to allow inbound port 5986.

A convenience script is available in `enable_winrm.ps1`.

### Salt master

- The `/etc/salt/roster` file must have a configuration section for every Windows machine you want to connect to. The configuration must have a local admin user and password for each machine, as in the following example.

```yaml
win2012dev: # Minion ID
  host: <IP address or hostname>
  user: <local Windows admin username>
  passwd: <password for the admin user>
  winrm: True
```

> **NOTE:** Domain credentials are not supported.

- Python 2 must be installed on the Salt master. The `salt-ssh` module for Windows is supported only on Python 2, not later versions.
- `pip` for Python 2 must be installed.

#### CentOS

To install `pip` for Python 2 on CentOS:

```bash
yum install epel-release -y
yum install python-pip
pip install -U setuptools
```

#### Ubuntu

To install `pip` for Python 2 on Ubuntu:

```bash
apt-get install python-pip
```

## Installation instructions

Download the latest release onto your Salt Master:

https://github.com/saltstack/saltwinshell/releases/download/v2017.7/saltwinshell-2017.7-cp27-cp27mu-linux_x86_64.whl

Install on your working Salt Master:

```
pip install -U ./saltwinshell-2017.7-cp27-cp27mu-linux_x86_64.whl
```

Once winrm is configured and running on your Windows system(s), you should be able to start using `salt-ssh`
against them.

```
salt-ssh <minion id> test.ping
```

The first time you run `salt-ssh` against a Windows minion it will take a bit
longer than usual since it has to deploy a working Salt python environment.
Subsequent runs should be much faster.

The shell libraries for agentless Windows to work via `salt-ssh`, installing
this library activates the ability to hit windows targets.

## Release process

- Create a new branch:

```
git checkout -b <new branch name>
```

- Make updates.
- Create a tag:

```
git tag -a v2018.3 -m "Version v2018.3 release" -s
git push origin 2018.3
git push --tags
```

- Copy in your python environment zip files to the root. Make sure they match
what the setup.py is expecting.
- Run the following:

  ```
  python setup.py bdist_wheel
  ```

  The file you want will be found in the `dist` directory and will look something  like:

  ```
  saltwinshell-2017.7-cp27-cp27mu-linux_x86_64.whl
  ```

- Upload `.whl` file as a new release on GitHub
