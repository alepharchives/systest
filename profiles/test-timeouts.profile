
{resource, ["resources/error_handling.resource"]}.
{targets,  [systest_timetraps_SUITE]}.
{hooks,    [{systest_timetraps_cth,
             [{teardown_timetrap,{seconds,10}},
              {aggressive_teardown,true}],
             100000},
            do_not_install,
            cth_log_redirect]}.
{aggressive_teardown, true}.
{teardown_timetrap, {seconds, 10}}.