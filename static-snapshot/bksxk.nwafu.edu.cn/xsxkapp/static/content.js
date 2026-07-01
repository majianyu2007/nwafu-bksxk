function initPage() {
    var id = $('#wid').val();
    var queryParam = {
        wid: id
    };
    queryNoticeView(queryParam).done(function(resp) {
        var code = resp.code;
        if (code != null && code == '1') {
            var data = resp.data;
            var title = data.title;
            var content = data.content;
            var time = data.timeDescription;
            $('#cv-title').html(title);
            $('#cv-content').html(content);
            $('#cv-time').html(time);
            if(data.filename){
            	$('.home-downloadfile .downloadfile').attr('href', $('.home-downloadfile .downloadfile').attr('href') + data.wid);
            	$('.home-downloadfile').show();
            }
        } else {
            $('#cv-title').html("无数据");
        }
    });
    /*queryCelebrityFamous().done(function(resp) {
		var code = resp.code;
		if(code != null && code == '1') {
			var dataList = resp.dataList;
			if(dataList != null && dataList.length > 0) {
				var randomIndex = RandomNumBoth(0, dataList.length - 1);
                initCelebrityFamous(dataList[randomIndex]);
			}
		}
	});*/
}

function initCelebrityFamous(_data) {
    $("#ecDiv").html(_data.englishContent);
    $("#cDiv").html(_data.content);
    $("#authorDiv").html(_data.author);
}

function RandomNumBoth(Min, Max) {
    var Range = Max - Min;
    var Rand = Math.random();
    var num = Min + Math.round(Rand * Range); //四舍五入
    return num;
}

function queryNoticeView(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/notice/view.do?timestamp=" + timestamp,
        queryParam,
        "get"
    );
}

function queryCelebrityFamous() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp=" + timestamp, {},
        "get"
    );
}

/**
 * 页脚信息
 */
;
(function(_mode) {

    _mode.init = function() {
        setCelebrityFamous();
        xsxkpub.changeCopyRight();
    };

    function setCelebrityFamous() {
        var dataList = JSON.parse(sessionStorage.getItem('celebrityFamous'));
        if (dataList != null && dataList.length > 0) {
            initFooterMessage(dataList[randomNumBoth(0, dataList.length - 1)]);
        } else {
            queryCelebrityFamous().done(function(resp) {
                var code = resp.code;
                if (code != null && code == '1') {
                    var dataList = resp.dataList;
                    if (dataList != null && dataList.length > 0) {
                        var randomIndex = randomNumBoth(0, dataList.length - 1);
                        initFooterMessage(dataList[randomIndex]);
                    }
                }
            });
        }
    };

    /**
     * 设置页面数据
     */
    function initFooterMessage(_data) {
        $("#ecDiv").html(_data.englishContent);
        $("#cDiv").html(_data.content);
        $("#authorDiv").html(_data.author);
    };

    /**
     * 数字区间取随机数
     */
    function randomNumBoth(Min, Max) {
        var Range = Max - Min;
        var Rand = Math.random();
        //四舍五入
        var num = Min + Math.round(Rand * Range);
        return num;
    };
})(window.CVFotterMessage = window.CVFotterMessage || {});


$(function() {
    initPage();
    // 设置页脚固定在页面底部
    setContentMinHeight($('.main').children('article'));

    CVFotterMessage.init();
});