*SysTest* is a framework aimed at distributed systems testing, with the
express purpose of making some common tasks easier and more manageable
for test authors and operators (who run tests).

The common factor that *SysTest* tries to address is the management and
monitoring of *Resources* required during testing. The idea of a
*Test(ing) Resource* is therefore central to *SysTest*, and as we will
see, has been made into a pervasive concept throughout the framework.
Indeed, the remainder of this text will concern itself with nothing
but *Resources*; What they are, How we interact with them and so on.

We will see that the *Resource* concept in *SysTest* provides a
flexible abstraction that

- can represent anything from a networked computer, to a file system directory
- can be controlled to ensure that all testing takes place in a consistent and stable environment
- can be composed to create arbitrarily complex test environments
- can be supervised to ensure it meets expected usage patterns
- can be configured to execute a user-defined, inter-connected component lifecycle 

In the next section, we will look at a concrete example of this.

## A Brief Example

Let us assume that we want to test a database application that has
been built in-house. In order to execute our tests, we want to run the
database server and application on one physical machine, and the test
client application on another, networked machine. In this example, the
test environment has a great many moving parts! We might consider any
or all of the following:

- environment/configuration for each machine
- configuration of the network
- installation and/or configuration of application(s) on either machine
- installation and/or configuration of application code
- the presence of static configuration files

To keep things simple, we will assume that the network is pervasive,
readily available and requires no configuration. In this scenario then,
we can separate the resources we care about into a few simple categories:

1. hosts (e.g., physical or virtual machines)
2. applications[*]
3. configuration files

In *SysTest*, we can categorise our resources into resource *types* and
define resources in terms of those types. Resource types define the
values and relationships (with other resource types) that they require
in order to be used - *realised* in *SysTest* parlance - and the individual
The resources we define *inject concrete (or derived) values into those types*
in order to make them usable at runtime.

Obviously this ability to define a resource type like `Host` with some
properties such as `host_name, ip_address` and so on is lovely, but quite
useless until we can actually *do something* with those values, like start
or provision a host with those settings. Although we have the ability to
define a *SysTest Resource Configuration Script* with all manner of types
and resources injecting values into those types, they can only be made to
do something useful if there is a *resource implementation* available at
runtime which can turn the values into something *real*. In practise,
this consists of an Erlang module which conforms to the `systest_resource`
behaviour. Several of these resource type implementations are provided
with *SysTest* and it is possible to define your own, custom implementations
and use these at runtime.

Without paying too much attention to the details of the configuration
script we're using, we will define these resource type

```
(the basic templates are:

requires            := mandatory relationship between resource types
a `with` b          := provided relationship between resources
is identified by    := identifying field
exposes             := property definitions
where               := property setting

)

alias ec2 for systest_ec2
    where
        aws_access_key_id     = #{settings.dbtest.ec2.id},
        aws_secret_access_key = #{settings.dbtest.ec2.key}.

alias script_runner for systest_proc
    provided by systest_cli,
    where
        "script"           = @{init_script},           (a @{deferred-variable} gets its value *later on*)
        env.USER           = 'dbuser',
        env.LOG_FILE       = /var/log/dbserver/@{id},  (all resources have an 'id' field!)
        env.DB_CONFIG_FILE = /etc/dbserver/config.

data Path
    is restricted by regex [^(.*?)([^/\\]*?)(\.[^/\\.]*)?$],
    is restricted by range [3..1024].

resource type Host "host"
    is identified by "name" (defaults to string),
    exposes IpAddress "ip_address".

resource type RemoteHost "remote host"
    realises Host,
    provided by ec2.

resource type Application "app"
    is identified by "app id",
    requires Path "init_script",
    requires context Host
        with Host.ip_address as "ip",
    provided by script_runner.

resource type ConfigFile "config file"
    is identified by Path "file_name",
    requires Path "source",
    requires context Host.

Application [db_client]
    where init_script = "/var/lib/dbclient/start".

resource type DbTest "database app test"
    requires "remote host" [host1.nat.mycorp.com] 
        (here we define a resource "inline" within the host)
        with Application [db_server]
            where init_script = /var/test/dbserver/start,
                (this next item is passed on to the systest_cli provider)
                  detached    = true
        with "config file" [/etc/dbserver/config]
            where source = ${settings.dbtest.server.config};
    requires Host [host2.nat.mycorp.com]
        (here we simply reference an existing resource, and
         if the types aren't compatible, we get an error)
        with db_client.
```

Or we can define the whole lot as raw Erlang terms if that is deemed preferable:

```erlang
{resource_type, 'Host', [
    {identified_by, 'name'},
    {exposes, [{'IpAddress', 'ip_address'}]},
    {provided_by, systest_host}
]}.
```

Clearly this categorisation of the *Resources* we wish to use for our tests
is insufficient to actually run them, as the two applications differ in
various ways, as do the host machines on which they run and the configuration
files required to set them up! This is where the ability to compose *Resources*
and *Resource Types* comes in:

Many of these concerns have been already solved in the industry at large,
and we do **not** want to reinvent the wheel, so *SysTest* does not attempt
to deal with any of the areas where solutions already exit. For example, we
are not concerned with

- provisioning or configuring the network
- provisioning physical or virtual machines
- configuring an operational machine (virtualised or otherwise)
- installing or configuring applications

There are numerous tools and frameworks available to do all these things
for us! Assuming we will use these tools to work on our behalf then, what
*SysTest* offers us is a means to describe the setup and teardown of the
test environment in terms of using those tools, and the means to have
the environment made available for the duration of our test(s) and have it
cleanly 'torn down' thereafter.

As we promised to make this example somewhat concrete, let's attempt to
fill in the gaps. We will assume that the following services are available
to us:

- we will provision a pair of networked machines using Amazon's EC2 service
- we will configure these machines using puppet
- we will also install and configure out database server and client using puppet

We can configure our two machines (with their different, respective setups)
very easily using puppet, so we do **not** need have 

In this case, the *resources* we wish to define will be:

1. the individual machines
2. 

## What *is* a resource anyway?

*SysTest* aims to be as generic a *testing support framework* as possible,
so from our point of view, a *Resource* is 'anything you want to use
in your tests', which is fairly permissive! In practise however, there are
of course some constraints, which we will discuss shortly.



to facilitate setting up the software you're testing, ensuring it stays online
for the duration of your tests, and cleanly tearing everything down after (and
between) each test.

*SysTest* is designed to work with any testing framework you choose, although
the stable branch currently supports on the OTP [_Common Test_][ct] framework. 
*SysTest* generally uses the same testing terminology as [_Common Test_][ct], 
with a few exceptions and additions that we will cover now.

## Scopes and naming conventions

Each execution of your tests is referred to as a _test run_, and as far as the 
framework is concerned, this consists of any and all running code from the 
moment that the [_Runner_][runner] is executed to the moment that control is
returned to the calling process.

Once a _test run_ starts, tests can be subdivided into _test suites_, which map
directly to [_Common Test_ `_SUITE` modules][ct_suites] when that framework is 
in use. Other testing frameworks (such as [eunit][eunit]), may choose to map a
test suite to a module or something other construct - refer to the framework
documentation to find out.

A _test suite_ will ...

## Runtime Environment

### The _System Under Test_

### The _Process_

[runner]: https://github.com/nebularis/systest/wiki/systest_runner
[eunit]: http://www.erlang.org/doc/apps/eunit/chapter.html
[ct_suites]: http://www.erlang.org/doc/apps/common_test/write_test_chapter.html
