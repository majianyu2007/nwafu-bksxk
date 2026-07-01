var pageSize = 10;
var pageNumber = 0;
var totalPage = 0;

/**
 * 根据信息类型初始化列表和标题
 */
;
(function(_model) {

	_model.init = function() {
		initType();
	};

	function initType() {
		var type = $('#informationType').val();
		var $title = $('#title');
		if (type == 'notice') {
			$title.html('通知公告');
			CVNoticeMode.init();
		} else if (type == 'problem') {
			$title.html('常见问题');
			CVProblemMode.init();
		}
	}

})(window.CVTitleMode = window.CVTitleMode || {});

/**
 * 初始化通知公告
 */
;
(function(_mode) {

	_mode.init = function() {
		initNotice();
	}

	function initNotice() {
		var queryParam = {
			'pageSize': pageSize,
			'pageNumber': pageNumber
		};
		queryNoticeList(queryParam).done(function(resp) {
			var code = resp.code;
			if (code != null && code != '') {
				var dataList = resp.dataList;
				buildNoticeList(dataList, resp.totalCount);
			}
		});
	}

	function buildNoticeList(dataList, totalCount) {
		if (dataList != null) {
			var length = dataList.length;
			var html = '';
			var data = null;
			for (var i = 0; i < length; i++) {
				data = dataList[i];
				var wrapTemplate = $('#tpl-notice-list-row').html();
				html += wrapTemplate.replace('@title', data.title)
					.replace('@time', data.timeDescription)
					.replace('@id', data.wid);
			}
			$('#cvPublicInfo').html(html);

			var footHtml = '';
			var footTemplate = $('#tel-notice-foot').html();
			totalPage = Math.ceil(totalCount / pageSize);
			footHtml = footTemplate.replace('@totalPage', totalPage)
				.replace('@pageNumber', pageNumber + 1);
			$('#cvPublicInfo').append(footHtml);

			bindPaging();
			bindOpenView();
		}
	}

	function bindPaging() {
		$('.paging').on('click', function(event) {
			var type = $(event.currentTarget).attr('type');
			if (type == "up" && pageNumber > 0) {
				pageNumber = pageNumber - 1;
			} else if (type == "down" && pageNumber < (totalPage - 1)) {
				pageNumber = pageNumber + 1;
			}
			initNotice();
		});
	}

	function bindOpenView() {
		$('.cv-title-link').on('click', function(event) {
			var id = $(event.currentTarget).attr('id');
			window.open(BaseUrl + "/sys/xsxkapp/*default/content.do?id=" + id);
		});
	}

})(window.CVNoticeMode = window.CVNoticeMode || {});

/**
 * 初始化常见问题
 */
;
(function(_model) {

	_model.init = function() {
		initProblem();
	}

	function initProblem() {
		queryProblemList().done(function(resp) {
			var code = resp.code;
			if (code != null && code != '') {
				var dataList = resp.dataList;
				buildProblemList(dataList);
			}
		});
	}

	function buildProblemList(dataList) {
		if (dataList != null) {
			var length = dataList.length;
			var html = '';
			var data = null;
			for (var i = 0; i < length; i++) {
				data = dataList[i];
				var wrapTemplate = $('#tpl-problem-list-row').html();
				html += wrapTemplate.replace('@title', data.title)
					.replace('@content', data.content);
			}
			$('#cvPublicInfo').html(html);
		}
	}

})(window.CVProblemMode = window.CVProblemMode || {});


/**
 * 页脚信息
 */
;
(function(_mode) {

	_mode.init = function() {
		setCelebrityFamous();
		xsxkpub.changeCopyRight();
	}

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
	CVTitleMode.init();

	// 设置页脚固定在页面底部
	setContentMinHeight($('.main').children('article'));

	CVFotterMessage.init();
});